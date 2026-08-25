import AppKit
import Combine

struct Candidate: Identifiable, Hashable {
    let id = UUID()
    let text: String
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
    private var generatingKey: String?     // 현재 생성 중 "paneKey|exKey"
    private var pending = false

    /// 수동 새로고침(버튼).
    func refreshFromTranscript() { Task { await refresh(force: true) } }

    /// 감시 트리거(포커스 전환·턴 이벤트).
    func refreshIfChanged() { Task { await refresh(force: false) } }

    func refresh(force: Bool) async {
        guard let info = orca.focusedPaneInfo() else { return }
        // 캐시 키 = 마지막 '제출한 프롬프트'만. 답변 스트리밍/완료로는 안 바뀌게 해서 왕복 시 캐시가 적중한다.
        let exKey = info.userPrompt ?? ""
        lastAnswerPreview = infoText(info)

        let genKey = info.paneKey + "|" + exKey

        // 1) 이 pane의 캐시가 최신이면 즉시 표시(전환 무지연) + 스피너 off.
        if !force, let c = cache[info.paneKey], c.key == exKey {
            candidates = c.cands
            isRefreshing = false
            log("HIT  pane=\(info.project) prompt=\"\(String(exKey.prefix(30)))\"")
            return
        }
        // 2) 최신 아님 → 이전(낡은) 후보는 숨기고 로딩 상태로 둔다(stale 표시가 혼동을 줘서).
        candidates = []
        isRefreshing = true

        // 3) 이 pane 생성이 진행 중이면 대기, 다른 pane 생성 중이면 큐잉(둘 다 로딩 유지).
        if generatingKey == genKey { return }
        if generatingKey != nil { pending = true; return }

        generatingKey = genKey
        let started = Date()
        log("GEN pane=\(info.project) state=\(info.state) prompt=\"\(String((info.userPrompt ?? "").prefix(40)))\"")

        let fresh = await generator.generate(from: Exchange(userPrompt: info.userPrompt, assistantAnswer: info.assistantAnswer))
        cache[info.paneKey] = (exKey, fresh)
        generatingKey = nil
        // 생성이 끝난 지금도 여전히 이 pane이 포커스면 화면 갱신 + 스피너 off. 다른 데로 갔으면 캐시만 채운다.
        if let now = orca.focusedPaneInfo(), now.paneKey == info.paneKey {
            candidates = fresh
            isRefreshing = false
        }
        let dt = String(format: "%.1f", Date().timeIntervalSince(started))
        log("RESULT \(fresh.count) cands in \(dt)s first=\"\(String(fresh.first?.text.prefix(30) ?? ""))\"")
        if pending { pending = false; await refresh(force: false) }
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

    /// 후보를 클립보드에 복사 → 사용자는 Orca에 붙여넣기만.
    func copy(_ candidate: Candidate) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(candidate.text, forType: .string)
    }
}
