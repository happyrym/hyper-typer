import AppKit
import Combine

struct Candidate: Identifiable, Hashable {
    let id = UUID()
    let text: String
}

/// 대화의 한 교환: 직전 사용자 프롬프트 + 어시스턴트 답변. 후보 생성의 입력.
struct Exchange {
    let userPrompt: String?
    let assistantAnswer: String?
}

/// 패널 상태: 포커스된 터미널의 정보 + 그 pane의 후보. pane별 후보 캐시로 전환은 무지연.
@MainActor
final class CandidateStore: ObservableObject {
    @Published var candidates: [Candidate] = []
    @Published var lastAnswerPreview: String = ""   // 헤더 info 라인(프로젝트·상태·직전 프롬프트)
    @Published var isRefreshing = false
    @Published var fontSize: CGFloat = 13           // 메뉴바에서 조절하는 후보 글씨 크기

    private let orca: FocusResolving
    private let generator: CandidateGenerating

    init(generator: CandidateGenerating = CandidateGenerator(), orca: FocusResolving = OrcaState()) {
        self.generator = generator
        self.orca = orca
    }

    // 포커스된 pane별 후보 캐시: paneKey → (교환 식별키, 후보들)
    private var cache: [String: (key: String, cands: [Candidate])] = [:]
    // 진행 중인 생성들의 "paneKey|exKey" 집합 — pane별 병렬 생성을 허용하고,
    // 동일 (pane, 답변) 조합의 중복 실행만 막는다. @MainActor라 락 없이 안전.
    private var inFlight: Set<String> = []

    /// 수동 새로고침(버튼).
    func refreshFromTranscript() { Task { await refresh(force: true) } }

    /// 감시 트리거(포커스 전환·턴 이벤트).
    func refreshIfChanged() { Task { await refresh(force: false) } }

    func refresh(force: Bool) async {
        guard let info = orca.focusedPaneInfo() else { return }
        lastAnswerPreview = infoText(info)

        let answer = (info.assistantAnswer ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // 답변이 준비됐을 때만(working=진행 중 제외) 생성 — 그 답변을 근거로 '사용자가 칠 다음 프롬프트'를 예측.
        // 답변 전엔 생성하지 않고 이 pane의 마지막 완료 후보를 유지한다(질문형 오답 방지).
        guard info.state != "working", !answer.isEmpty else {
            if let c = cache[info.paneKey] { candidates = c.cands }
            isRefreshing = false
            return
        }

        // 캐시 키 = 답변(턴 완료마다 갱신). 왕복·스트리밍엔 안 바뀌어 캐시가 적중한다.
        let exKey = answer
        let genKey = info.paneKey + "|" + exKey

        // 1) 이 pane의 캐시가 최신이면 즉시 표시(전환 무지연) + 스피너 off.
        if !force, let c = cache[info.paneKey], c.key == exKey {
            candidates = c.cands
            isRefreshing = false
            log("HIT  pane=\(info.project)")
            return
        }
        // 2) 최신 아님 → 이전(낡은) 후보는 숨기고 로딩 상태로 둔다.
        candidates = []
        isRefreshing = true

        // 3) 이 (pane, 답변) 생성이 이미 진행 중이면 중복 실행하지 않는다(완료 콜백이 화면을 갱신).
        //    다른 pane이 생성 중이어도 막지 않는다 — 각 pane이 독립적으로 병렬 생성된다.
        if inFlight.contains(genKey) { return }
        inFlight.insert(genKey)
        let started = Date()
        log("GEN pane=\(info.project) answer=\"\(String(answer.prefix(40)))\"")

        let fresh = await generator.generate(from: Exchange(userPrompt: info.userPrompt, assistantAnswer: info.assistantAnswer))

        inFlight.remove(genKey)
        cache[info.paneKey] = (exKey, fresh)
        // 화면 반영은 '완료 시점에도 이 pane이 포커스이고 그 답변이 여전히 최신'일 때만.
        // 그 사이 다른 pane으로 옮겼거나 새 턴이 오면 결과가 낡은 것이므로 화면·스피너를 건드리지 않는다
        // (다른 pane의 진행 중 스피너를 잘못 끄는 것을 방지).
        if let cur = orca.focusedPaneInfo(),
           cur.paneKey == info.paneKey,
           (cur.assistantAnswer ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == exKey {
            candidates = fresh
            isRefreshing = false
        }
        let dt = String(format: "%.1f", Date().timeIntervalSince(started))
        log("RESULT \(fresh.count) cands in \(dt)s first=\"\(String(fresh.first?.text.prefix(30) ?? ""))\"")
    }

    private func infoText(_ info: PaneInfo) -> String {
        let prompt = info.userPrompt.map { String($0.prefix(40)) } ?? ""
        let st = info.state.isEmpty ? "" : " · \(info.state)"
        return "\(info.project)\(st)  ·  \(prompt)"
    }

    /// 안정성 검증용 디버그 로그(~/.hyper-typer/hyper-typer.log).
    private func log(_ msg: String) {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hyper-typer/hyper-typer.log")
        guard let data = "\(Date()) \(msg)\n".data(using: .utf8) else { return }
        if let fh = try? FileHandle(forWritingTo: url) {
            defer { try? fh.close() }
            fh.seekToEndOfFile()
            fh.write(data)
        } else {
            try? data.write(to: url)
        }
    }

    /// 특정 pane에 캐시된 후보(없으면 nil). 병렬 생성 검증·디버그용.
    func cachedCandidates(forPane paneKey: String) -> [Candidate]? { cache[paneKey]?.cands }

    /// 슬롯 번호(0-based)의 후보 텍스트. 범위 밖이면 nil.
    func candidateText(at index: Int) -> String? {
        guard index >= 0, index < candidates.count else { return nil }
        return candidates[index].text
    }

    /// 후보를 클립보드에 복사 → 사용자는 Orca에 붙여넣기만.
    func copy(_ candidate: Candidate) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(candidate.text, forType: .string)
    }
}
