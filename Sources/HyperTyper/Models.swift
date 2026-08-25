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

    private let orca = OrcaState()
    private let generator = CandidateGenerator()

    // 포커스된 pane별 후보 캐시: paneKey → (교환 식별키, 후보들)
    private var cache: [String: (key: String, cands: [Candidate])] = [:]
    private var generatingKey: String?     // 현재 생성 중 "paneKey|exKey"
    private var pending = false

    /// 수동 새로고침(버튼).
    func refreshFromTranscript() { Task { await refresh(force: true) } }

    /// 감시 트리거(포커스 전환·턴 이벤트).
    func refreshIfChanged() { Task { await refresh(force: false) } }

    private func refresh(force: Bool) async {
        guard let info = orca.focusedPaneInfo() else { return }
        // 캐시 키 = 마지막 '제출한 프롬프트'만. 답변 스트리밍/완료로는 안 바뀌게 해서 왕복 시 캐시가 적중한다.
        let exKey = info.userPrompt ?? ""
        lastAnswerPreview = infoText(info)

        // 1) 이 pane의 캐시가 최신이면 즉시 표시(전환 무지연). 강제 새로고침이면 건너뜀.
        if !force, let c = cache[info.paneKey], c.key == exKey {
            candidates = c.cands
            log("HIT  pane=\(info.project) prompt=\"\(String(exKey.prefix(30)))\"")
            return
        }
        // 2) 낡은 캐시라도 있으면 먼저 보여줘 빈 화면 방지.
        if let c = cache[info.paneKey] { candidates = c.cands }

        // 3) 동일 pane+교환 생성이 진행 중이면 중복 방지. 다른 생성 중이면 큐잉.
        let genKey = info.paneKey + "|" + exKey
        if generatingKey == genKey { return }
        if generatingKey != nil { pending = true; return }

        generatingKey = genKey
        isRefreshing = true
        let started = Date()
        log("GEN pane=\(info.project) state=\(info.state) prompt=\"\(String((info.userPrompt ?? "").prefix(40)))\"")

        let fresh = await generator.generate(from: Exchange(userPrompt: info.userPrompt, assistantAnswer: info.assistantAnswer))
        cache[info.paneKey] = (exKey, fresh)
        // 생성이 끝난 지금도 여전히 이 pane이 포커스면 화면 갱신(그새 다른 터미널로 갔으면 캐시만 채움).
        if let now = orca.focusedPaneInfo(), now.paneKey == info.paneKey {
            candidates = fresh
        }
        let dt = String(format: "%.1f", Date().timeIntervalSince(started))
        log("RESULT \(fresh.count) cands in \(dt)s first=\"\(String(fresh.first?.text.prefix(30) ?? ""))\"")
        isRefreshing = false
        generatingKey = nil
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
