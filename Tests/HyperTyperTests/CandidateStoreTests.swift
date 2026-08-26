import XCTest
@testable import HyperTyper

/// LLM(claude CLI) mock. 호출 횟수만 세고 고정 후보를 돌려준다.
private final class MockGenerator: CandidateGenerating, @unchecked Sendable {
    private(set) var callCount = 0
    var response: [Candidate]
    init(response: [Candidate] = [Candidate(text: "mock")]) { self.response = response }
    func generate(from exchange: Exchange) async -> [Candidate] {
        callCount += 1
        return response
    }
}

/// 포커스 pane 주입 mock.
private final class MockOrca: FocusResolving, @unchecked Sendable {
    var info: PaneInfo?
    func focusedPaneInfo() -> PaneInfo? { info }
}

/// 생성 '도중' 포커스 상태가 바뀌는 상황을 재현하는 mock — 병렬 생성의 낡은 결과 폐기 가드 검증용.
private final class FocusMutatingGenerator: CandidateGenerating, @unchecked Sendable {
    let orca: MockOrca
    let during: PaneInfo
    let response: [Candidate]
    init(orca: MockOrca, during: PaneInfo, response: [Candidate]) {
        self.orca = orca; self.during = during; self.response = response
    }
    func generate(from exchange: Exchange) async -> [Candidate] {
        orca.info = during   // 생성이 끝나기 전 포커스/답변이 바뀐 상태로 만든다
        return response
    }
}

/// 완료 시점을 테스트가 제어하는 생성기 — 답변(exKey)별로 continuation을 붙잡아
/// 두 refresh Task가 실제로 동시에 in-flight가 되는 인터리빙을 재현한다(@MainActor 단일 스레드).
private final class ControllableGenerator: CandidateGenerating, @unchecked Sendable {
    private(set) var callCount = 0
    private var continuations: [String: CheckedContinuation<Void, Never>] = [:]
    var responses: [String: [Candidate]] = [:]
    func generate(from exchange: Exchange) async -> [Candidate] {
        let key = (exchange.assistantAnswer ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        callCount += 1
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in continuations[key] = c }
        return responses[key] ?? [Candidate(text: "gen:\(key)")]
    }
    func isWaiting(_ key: String) -> Bool { continuations[key] != nil }
    func release(_ key: String) { continuations.removeValue(forKey: key)?.resume() }
}

/// 후보는 '답변'을 근거로 생성되므로 캐시 키도 답변 기준. 헬퍼는 answer를 변수로 둔다.
private func pane(_ key: String, answer: String, state: String = "done", project: String = "proj") -> PaneInfo {
    PaneInfo(paneKey: key, cwd: "/x/\(project)", project: project,
             state: state, userPrompt: "p", assistantAnswer: answer)
}

@MainActor
final class CandidateStoreTests: XCTestCase {

    func testGeneratesWhenAnswerReady() async {
        let gen = MockGenerator(response: [Candidate(text: "a")])
        let orca = MockOrca(); orca.info = pane("p:1", answer: "done answer")
        let store = CandidateStore(generator: gen, orca: orca)
        await store.refresh(force: false)
        XCTAssertEqual(gen.callCount, 1)
        XCTAssertEqual(store.candidates.map { $0.text }, ["a"])
    }

    func testCacheHitAvoidsRegeneration() async {
        let gen = MockGenerator()
        let orca = MockOrca(); orca.info = pane("p:1", answer: "same")
        let store = CandidateStore(generator: gen, orca: orca)
        await store.refresh(force: false)
        await store.refresh(force: false)   // 같은 pane+답변 → 캐시 적중, 재생성 없음
        XCTAssertEqual(gen.callCount, 1)
    }

    func testAnswerChangeRegenerates() async {
        let gen = MockGenerator()
        let orca = MockOrca(); orca.info = pane("p:1", answer: "answer1")
        let store = CandidateStore(generator: gen, orca: orca)
        await store.refresh(force: false)
        orca.info = pane("p:1", answer: "answer2")   // 새 턴 완료 → 새 답변
        await store.refresh(force: false)
        XCTAssertEqual(gen.callCount, 2)
    }

    /// 터미널별 캐시 격리 — A→B→A 왕복 시 A는 캐시 적중.
    func testPerPaneCacheIsolation() async {
        let gen = MockGenerator()
        let orca = MockOrca(); orca.info = pane("A:1", answer: "aa")
        let store = CandidateStore(generator: gen, orca: orca)
        await store.refresh(force: false)          // A 생성 (1)
        orca.info = pane("B:1", answer: "bb")
        await store.refresh(force: false)          // B 생성 (2)
        orca.info = pane("A:1", answer: "aa")
        await store.refresh(force: false)          // A로 복귀 → 캐시 적중 (여전히 2)
        XCTAssertEqual(gen.callCount, 2)
    }

    /// 진행 중(working)에는 생성하지 않는다 — 답변이 없어 질문형 오답을 막기 위함.
    func testWorkingStateSkipsGeneration() async {
        let gen = MockGenerator()
        let orca = MockOrca(); orca.info = pane("p:1", answer: "prev", state: "working")
        let store = CandidateStore(generator: gen, orca: orca)
        await store.refresh(force: false)
        XCTAssertEqual(gen.callCount, 0)
    }

    func testEmptyAnswerSkipsGeneration() async {
        let gen = MockGenerator()
        let orca = MockOrca(); orca.info = pane("p:1", answer: "")
        let store = CandidateStore(generator: gen, orca: orca)
        await store.refresh(force: false)
        XCTAssertEqual(gen.callCount, 0)
    }

    func testForceAlwaysRegenerates() async {
        let gen = MockGenerator()
        let orca = MockOrca(); orca.info = pane("p:1", answer: "x")
        let store = CandidateStore(generator: gen, orca: orca)
        await store.refresh(force: false)
        await store.refresh(force: true)   // 강제 새로고침은 캐시 무시
        XCTAssertEqual(gen.callCount, 2)
    }

    func testNoPaneInfoDoesNothing() async {
        let gen = MockGenerator()
        let orca = MockOrca(); orca.info = nil
        let store = CandidateStore(generator: gen, orca: orca)
        await store.refresh(force: false)
        XCTAssertEqual(gen.callCount, 0)
        XCTAssertTrue(store.candidates.isEmpty)
    }

    /// 병렬 생성: A 생성이 끝났을 때 포커스가 이미 B로 옮겨졌으면 A 결과로 화면을 덮지 않는다.
    func testBackgroundCompletionDoesNotClobberFocusedPane() async {
        let orca = MockOrca(); orca.info = pane("A:1", answer: "aa")
        let gen = FocusMutatingGenerator(orca: orca,
                                         during: pane("B:1", answer: "bb"),
                                         response: [Candidate(text: "A-result")])
        let store = CandidateStore(generator: gen, orca: orca)
        await store.refresh(force: false)
        XCTAssertNotEqual(store.candidates.map { $0.text }, ["A-result"])
        XCTAssertEqual(store.cachedCandidates(forPane: "A:1")?.map { $0.text }, ["A-result"])  // 캐시엔 남는다
    }

    /// 병렬 생성: 같은 pane에서 생성 도중 새 턴(새 답변)이 오면, 낡은 답변의 결과는 화면에 반영하지 않는다.
    func testStaleAnswerResultDiscarded() async {
        let orca = MockOrca(); orca.info = pane("A:1", answer: "answer1")
        let gen = FocusMutatingGenerator(orca: orca,
                                         during: pane("A:1", answer: "answer2"),
                                         response: [Candidate(text: "old")])
        let store = CandidateStore(generator: gen, orca: orca)
        await store.refresh(force: false)
        XCTAssertNotEqual(store.candidates.map { $0.text }, ["old"])
    }

    /// 동시에 같은 (pane, 답변)로 refresh가 두 번 들어와도 생성은 한 번만 실행된다(inFlight 중복 차단).
    func testConcurrentSameGenKeyDedup() async {
        let orca = MockOrca(); orca.info = pane("p:1", answer: "X")
        let gen = ControllableGenerator()
        let store = CandidateStore(generator: gen, orca: orca)
        let t1 = Task { await store.refresh(force: false) }   // 생성 시작 후 continuation에서 대기
        while !gen.isWaiting("X") { await Task.yield() }
        await store.refresh(force: false)                     // 같은 genKey → 즉시 반환, 재생성 없음
        XCTAssertEqual(gen.callCount, 1)
        gen.release("X"); _ = await t1.value
        XCTAssertEqual(store.candidates.map { $0.text }, ["gen:X"])
    }

    /// 완료 역전(A2가 A1보다 먼저 끝남) 시, 낡은 A1 결과가 최신 A2 캐시·화면을 덮어쓰지 않는다(Fix B).
    func testOutOfOrderCompletionKeepsLatest() async {
        let orca = MockOrca(); orca.info = pane("p:1", answer: "A1")
        let gen = ControllableGenerator()
        gen.responses = ["A1": [Candidate(text: "r1")], "A2": [Candidate(text: "r2")]]
        let store = CandidateStore(generator: gen, orca: orca)
        let t1 = Task { await store.refresh(force: false) }   // A1 생성 시작 → 대기
        while !gen.isWaiting("A1") { await Task.yield() }
        orca.info = pane("p:1", answer: "A2")                 // 새 턴
        let t2 = Task { await store.refresh(force: false) }   // A2 생성 시작 → 대기
        while !gen.isWaiting("A2") { await Task.yield() }
        gen.release("A2"); _ = await t2.value                 // 최신이 먼저 완료
        gen.release("A1"); _ = await t1.value                 // 낡은 것이 나중 완료(덮어쓰면 안 됨)
        XCTAssertEqual(store.cachedCandidates(forPane: "p:1")?.map { $0.text }, ["r2"])
        XCTAssertEqual(store.candidates.map { $0.text }, ["r2"])
    }

    /// 생성 진행 중 같은 pane에 새 턴(working)이 오면 스피너를 유지한다(Fix A — 빈 패널 깜빡임 방지).
    func testNewTurnDuringGenerationKeepsSpinner() async {
        let orca = MockOrca(); orca.info = pane("p:1", answer: "A1")
        let gen = ControllableGenerator()
        let store = CandidateStore(generator: gen, orca: orca)
        let t1 = Task { await store.refresh(force: false) }   // A1 생성 시작 → isRefreshing=true, 대기
        while !gen.isWaiting("A1") { await Task.yield() }
        XCTAssertTrue(store.isRefreshing)
        orca.info = pane("p:1", answer: "", state: "working") // 새 턴: 진행 중, 답변 비어 있음
        await store.refresh(force: false)
        XCTAssertTrue(store.isRefreshing, "생성 진행 중엔 새 턴 시작에도 스피너를 유지해야 한다")
        gen.release("A1"); _ = await t1.value
    }
}
