import AppKit
import Combine

struct Candidate: Identifiable, Hashable {
    let id = UUID()
    let text: String
}

/// 패널 상태: 직전 답변 프리뷰 + 후보 5개 + 로딩 여부. 복사 처리도 담당.
@MainActor
final class CandidateStore: ObservableObject {
    @Published var candidates: [Candidate] = []
    @Published var lastAnswerPreview: String = ""
    @Published var isRefreshing = false        // 헤더 인디케이터용. 목록은 가리지 않는다.

    private let reader = TranscriptReader()
    private let generator = CandidateGenerator()
    private var lastSeenUserPrompt: String?
    private var isGenerating = false           // 동시 생성 방지
    private var pending = false                // 생성 중 새 변경이 오면 끝나고 한 번 더

    /// 수동 새로고침(버튼): 무조건 재생성.
    func refreshFromTranscript() { Task { await run(force: true) } }

    /// 파일 변경 감지 시: 직전 답변이 실제로 바뀌었을 때만 재생성.
    func refreshIfChanged() { Task { await run(force: false) } }

    /// 후보의 근거가 될 마지막 교환(사용자 프롬프트+답변)을 정한다.
    /// 1순위: Stop hook이 기록한 last-turn.json의 transcript_path(= 방금 답한 그 세션).
    /// 폴백: 가장 최근 활동 세션.
    private func resolveExchange() -> Exchange {
        // 터미널별 스코핑: 가장 최근 '새 user 발화'가 있는 세션(= 내가 방금 제출한 터미널).
        // 백그라운드 에이전트(assistant만 append)는 이 선택을 못 바꿔 크로스 트리거가 막힌다.
        reader.mostRecentUserExchange()
    }

    private func run(force: Bool) async {
        let exchange = resolveExchange()
        // 트리거 기준 = 내가 방금 '엔터로 제출한' 프롬프트(= 새 user 메시지). Shift+Enter는 제출이 아니라
        // transcript에 안 남으므로 자연히 걸러진다. 답변을 기다리지 않고 제출 즉시 다음 수를 예측.
        let submitted = exchange.userPrompt
        if !force, submitted == lastSeenUserPrompt { return }
        if isGenerating { pending = true; return }   // 진행 중이면 큐잉만

        isGenerating = true
        isRefreshing = true
        lastSeenUserPrompt = submitted
        lastAnswerPreview = String((submitted ?? "").prefix(120))
        let started = Date()
        log("TRIGGER force=\(force) submitted=\"\(String((submitted ?? "").prefix(40)))\"")

        let fresh = await generator.generate(from: exchange)
        candidates = fresh          // 다 만든 뒤 한 번에 교체 → 목록이 비지 않음(깜빡임 제거)
        let dt = String(format: "%.1f", Date().timeIntervalSince(started))
        log("RESULT \(fresh.count) cands in \(dt)s first=\"\(String(fresh.first?.text.prefix(30) ?? ""))\"")
        isRefreshing = false
        isGenerating = false

        if pending { pending = false; await run(force: false) }
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
