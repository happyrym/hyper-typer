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

    // 후보는 두 스트림으로 나뉘어 pane별로 각각 캐시된다:
    //  · early  — 프롬프트만으로(답변 무관) 생성한 3개. 새 프롬프트를 보내는 순간 즉시 뜬다.
    //  · answer — 답변 기반 3개. 답변이 완료되면 early 뒤에 덧붙는다.
    // 화면 = (프롬프트 일치하는 early) + (답변 일치하는 answer), 최대 6개.
    private enum Stream: String { case early, answer }
    private struct Slot { let key: String; let cands: [Candidate] }
    private var earlyCache: [String: Slot] = [:]
    private var answerCache: [String: Slot] = [:]
    // 진행 중인 생성 "stream|paneKey|key" — pane·스트림별 병렬 허용, 동일 조합 중복만 차단. @MainActor라 락 불필요.
    private var inFlight: Set<String> = []
    // "stream|paneKey" → 가장 최근에 시작된 생성 순번. 완료 역전 시 낡은 결과의 캐시 덮어쓰기를 막는다.
    private var seqMap: [String: Int] = [:]

    private static let earlyCount = 3
    private static let answerCount = 3

    /// 수동 새로고침(버튼).
    func refreshFromTranscript() { Task { await refresh(force: true) } }

    /// 감시 트리거(포커스 전환·턴 이벤트).
    func refreshIfChanged() { Task { await refresh(force: false) } }

    func refresh(force: Bool) async {
        guard let info = orca.focusedPaneInfo() else { return }
        lastAnswerPreview = infoText(info)
        let prompt = trimmed(info.userPrompt)
        let answerKey = trimmed(info.assistantAnswer)
        let answerReady = info.state != "working" && !answerKey.isEmpty

        // 현재 캐시로 화면·스피너를 먼저 구성(전환 무지연).
        recompute(info)

        // early(답변 무관)는 프롬프트만 있으면, answer(답변 기반)는 답변 준비 시. 두 스트림은 독립 병렬.
        await withTaskGroup(of: Void.self) { group in
            if !prompt.isEmpty {
                group.addTask { await self.generate(.early, info: info, key: prompt, force: force) }
            }
            if answerReady {
                group.addTask { await self.generate(.answer, info: info, key: answerKey, force: force) }
            }
        }
    }

    private func generate(_ stream: Stream, info: PaneInfo, key: String, force: Bool) async {
        let flightKey = "\(stream.rawValue)|\(info.paneKey)|\(key)"
        let seqKey = "\(stream.rawValue)|\(info.paneKey)"
        let have = (stream == .early ? earlyCache : answerCache)[info.paneKey]
        if !force, have?.key == key { return }        // 이미 최신 → 재생성 불필요
        if inFlight.contains(flightKey) { return }     // 이미 진행 중 → 중복 방지
        inFlight.insert(flightKey)
        let seq = (seqMap[seqKey] ?? 0) + 1
        seqMap[seqKey] = seq
        updateSpinner(info)
        let started = Date()
        log("GEN \(stream.rawValue) pane=\(info.project) key=\"\(String(key.prefix(40)))\"")

        // early는 답변을 빼고 프롬프트만으로 예측(진짜 '답변 무관'). answer는 답변까지 넣어 예측.
        let exchange = stream == .early
            ? Exchange(userPrompt: info.userPrompt, assistantAnswer: nil)
            : Exchange(userPrompt: info.userPrompt, assistantAnswer: info.assistantAnswer)
        let n = stream == .early ? Self.earlyCount : Self.answerCount
        let fresh = await generator.generate(from: exchange, count: n)

        inFlight.remove(flightKey)
        // 최신 생성일 때만 캐시 반영 — 완료 순서가 뒤바뀌어도 낡은 결과가 최신을 덮어쓰지 않는다.
        if seqMap[seqKey] == seq {
            let slot = Slot(key: key, cands: fresh)
            if stream == .early { earlyCache[info.paneKey] = slot } else { answerCache[info.paneKey] = slot }
        }
        // 완료 시점에도 이 pane이 포커스면 화면 갱신(다른 pane으로 옮겼으면 그 pane 몫이므로 건드리지 않음).
        if let cur = orca.focusedPaneInfo(), cur.paneKey == info.paneKey { recompute(cur) }
        let dt = String(format: "%.1f", Date().timeIntervalSince(started))
        log("RESULT \(stream.rawValue) \(fresh.count) cands in \(dt)s")
    }

    /// 두 스트림 캐시를 현재 pane 상태에 맞춰 합쳐 화면(candidates)과 스피너를 구성한다.
    private func recompute(_ info: PaneInfo) {
        let prompt = trimmed(info.userPrompt)
        let answer = trimmed(info.assistantAnswer)
        let answerReady = info.state != "working" && !answer.isEmpty
        var out: [Candidate] = []
        if let e = earlyCache[info.paneKey], e.key == prompt { out += e.cands }
        if answerReady, let a = answerCache[info.paneKey], a.key == answer { out += a.cands }
        candidates = out
        updateSpinner(info)
    }

    /// 표시할 후보가 아직 없고 이 pane에 대해 뭔가 생성 중이면 스피너를 켠다(paneKey엔 '|'가 없어 경계가 안전).
    private func updateSpinner(_ info: PaneInfo) {
        isRefreshing = candidates.isEmpty && inFlight.contains { $0.contains("|\(info.paneKey)|") }
    }

    private func trimmed(_ s: String?) -> String {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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

    /// 특정 pane에 캐시된 후보(early + answer, 없으면 nil). 병렬 생성 검증·디버그용.
    func cachedCandidates(forPane paneKey: String) -> [Candidate]? {
        let all = (earlyCache[paneKey]?.cands ?? []) + (answerCache[paneKey]?.cands ?? [])
        return all.isEmpty ? nil : all
    }

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
