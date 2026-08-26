import XCTest
@testable import HyperTyper

/// LLM(claude CLI) mock. early(답변 nil)는 "E1..", answer(답변 있음)는 "A1.." 로 태그해 스트림을 구분.
/// generate는 MainActor 밖(제너릭 executor)에서 병렬 호출될 수 있어 callCount를 락으로 보호한다.
private final class MockGenerator: CandidateGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var _callCount = 0
    var callCount: Int { lock.lock(); defer { lock.unlock() }; return _callCount }
    func generate(from exchange: Exchange, count: Int) async -> [Candidate] {
        lock.lock(); _callCount += 1; lock.unlock()
        let tag = exchange.assistantAnswer == nil ? "E" : "A"
        return (1...count).map { Candidate(text: "\(tag)\($0)") }
    }
}

/// 포커스 pane 주입 mock.
private final class MockOrca: FocusResolving, @unchecked Sendable {
    var info: PaneInfo?
    func focusedPaneInfo() -> PaneInfo? { info }
}

/// 완료 시점을 테스트가 제어하는 생성기 — 스트림별 키("E:프롬프트" / "A:답변")로 continuation을 붙잡아
/// 두 생성이 실제로 동시에 in-flight가 되는 인터리빙을 재현한다. MainActor 밖 접근이라 락으로 보호.
private final class ControllableGenerator: CandidateGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var _callCount = 0
    private var continuations: [String: CheckedContinuation<Void, Never>] = [:]
    var responses: [String: [Candidate]] = [:]
    var callCount: Int { lock.lock(); defer { lock.unlock() }; return _callCount }
    private func key(_ ex: Exchange) -> String {
        if let a = ex.assistantAnswer { return "A:\(a.trimmingCharacters(in: .whitespacesAndNewlines))" }
        return "E:\((ex.userPrompt ?? "").trimmingCharacters(in: .whitespacesAndNewlines))"
    }
    func generate(from exchange: Exchange, count: Int) async -> [Candidate] {
        let k = key(exchange)
        lock.lock(); _callCount += 1; lock.unlock()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            lock.lock(); continuations[k] = c; lock.unlock()
        }
        lock.lock(); let r = responses[k]; lock.unlock()
        return r ?? [Candidate(text: "gen:\(k)")]
    }
    func isWaiting(_ k: String) -> Bool { lock.lock(); defer { lock.unlock() }; return continuations[k] != nil }
    func release(_ k: String) { lock.lock(); let c = continuations.removeValue(forKey: k); lock.unlock(); c?.resume() }
}

private func pane(_ key: String, answer: String, state: String = "done",
                  project: String = "proj", prompt: String = "p") -> PaneInfo {
    PaneInfo(paneKey: key, cwd: "/x/\(project)", project: project,
             state: state, userPrompt: prompt, assistantAnswer: answer)
}

@MainActor
final class CandidateStoreTests: XCTestCase {

    /// 답변 완료 pane → early 3 + answer 3 = 6개, 생성 2회.
    func testAnswerReadyGeneratesEarlyAndAnswer() async {
        let gen = MockGenerator()
        let orca = MockOrca(); orca.info = pane("p:1", answer: "done")
        let store = CandidateStore(generator: gen, orca: orca)
        await store.refresh(force: false)
        XCTAssertEqual(gen.callCount, 2)
        XCTAssertEqual(store.candidates.map { $0.text }, ["E1", "E2", "E3", "A1", "A2", "A3"])
    }

    /// 진행 중(working) pane → early 3만, answer는 생성 안 함.
    func testWorkingGeneratesOnlyEarly() async {
        let gen = MockGenerator()
        let orca = MockOrca(); orca.info = pane("p:1", answer: "", state: "working")
        let store = CandidateStore(generator: gen, orca: orca)
        await store.refresh(force: false)
        XCTAssertEqual(gen.callCount, 1)
        XCTAssertEqual(store.candidates.map { $0.text }, ["E1", "E2", "E3"])
    }

    /// 같은 프롬프트+답변 → 두 스트림 모두 캐시 적중, 재생성 없음.
    func testCacheHitAvoidsRegeneration() async {
        let gen = MockGenerator()
        let orca = MockOrca(); orca.info = pane("p:1", answer: "done")
        let store = CandidateStore(generator: gen, orca: orca)
        await store.refresh(force: false)
        await store.refresh(force: false)
        XCTAssertEqual(gen.callCount, 2)
    }

    /// early는 프롬프트 기준이라 답변이 와도 유지되고, answer 3개가 뒤에 덧붙는다.
    func testEarlyPersistsAnswerAppends() async {
        let gen = MockGenerator()
        let orca = MockOrca(); orca.info = pane("p:1", answer: "", state: "working")
        let store = CandidateStore(generator: gen, orca: orca)
        await store.refresh(force: false)                       // early만
        XCTAssertEqual(store.candidates.map { $0.text }, ["E1", "E2", "E3"])
        orca.info = pane("p:1", answer: "ans", state: "done")   // 답변 완료(프롬프트 동일)
        await store.refresh(force: false)                       // answer만 추가 생성
        XCTAssertEqual(gen.callCount, 2)
        XCTAssertEqual(store.candidates.map { $0.text }, ["E1", "E2", "E3", "A1", "A2", "A3"])
    }

    /// 터미널별 캐시 격리 — A→B→A 왕복 시 A는 캐시 적중(같은 프롬프트 문자열이어도 paneKey로 분리).
    func testPerPaneIsolation() async {
        let gen = MockGenerator()
        let orca = MockOrca(); orca.info = pane("A:1", answer: "aa")
        let store = CandidateStore(generator: gen, orca: orca)
        await store.refresh(force: false)          // A: 2회
        orca.info = pane("B:1", answer: "bb")
        await store.refresh(force: false)          // B: 2회 (누적 4)
        orca.info = pane("A:1", answer: "aa")
        await store.refresh(force: false)          // A 복귀 → 캐시 적중 (여전히 4)
        XCTAssertEqual(gen.callCount, 4)
    }

    /// 강제 새로고침은 두 스트림 모두 캐시 무시하고 재생성.
    func testForceRegeneratesBoth() async {
        let gen = MockGenerator()
        let orca = MockOrca(); orca.info = pane("p:1", answer: "done")
        let store = CandidateStore(generator: gen, orca: orca)
        await store.refresh(force: false)          // 2
        await store.refresh(force: true)           // +2
        XCTAssertEqual(gen.callCount, 4)
    }

    func testNoPaneInfoDoesNothing() async {
        let gen = MockGenerator()
        let orca = MockOrca(); orca.info = nil
        let store = CandidateStore(generator: gen, orca: orca)
        await store.refresh(force: false)
        XCTAssertEqual(gen.callCount, 0)
        XCTAssertTrue(store.candidates.isEmpty)
    }

    /// 프롬프트·답변 둘 다 없으면 아무것도 생성하지 않는다.
    func testEmptyPromptAndAnswerDoesNothing() async {
        let gen = MockGenerator()
        let orca = MockOrca(); orca.info = pane("p:1", answer: "", state: "working", prompt: "")
        let store = CandidateStore(generator: gen, orca: orca)
        await store.refresh(force: false)
        XCTAssertEqual(gen.callCount, 0)
        XCTAssertTrue(store.candidates.isEmpty)
    }

    /// 완료 역전(새 답변 A2가 낡은 A1보다 먼저 끝남) 시, A1 결과가 최신 A2 캐시·화면을 덮어쓰지 않는다.
    func testOutOfOrderAnswerCompletionKeepsLatest() async {
        let orca = MockOrca(); orca.info = pane("p:1", answer: "A1")
        let gen = ControllableGenerator()
        gen.responses = ["E:p": [Candidate(text: "e")],
                         "A:A1": [Candidate(text: "a1")],
                         "A:A2": [Candidate(text: "a2")]]
        let store = CandidateStore(generator: gen, orca: orca)
        let t1 = Task { await store.refresh(force: false) }     // E:p + A:A1 시작
        while !(gen.isWaiting("E:p") && gen.isWaiting("A:A1")) { await Task.yield() }
        gen.release("E:p")                                       // early 먼저 완료
        orca.info = pane("p:1", answer: "A2")                    // 새 턴 답변 A2
        let t2 = Task { await store.refresh(force: false) }      // A:A2 시작(early는 캐시 적중)
        while !gen.isWaiting("A:A2") { await Task.yield() }
        gen.release("A:A2")                                      // 최신이 먼저 완료
        gen.release("A:A1")                                      // 낡은 것이 나중 완료
        _ = await t1.value; _ = await t2.value
        XCTAssertEqual(store.cachedCandidates(forPane: "p:1")?.map { $0.text }, ["e", "a2"])
        XCTAssertEqual(store.candidates.map { $0.text }, ["e", "a2"])
    }

    /// 같은 스트림+키로 동시에 refresh가 들어와도 생성은 한 번만(inFlight 중복 차단).
    func testConcurrentSameStreamKeyDedup() async {
        let orca = MockOrca(); orca.info = pane("p:1", answer: "", state: "working")
        let gen = ControllableGenerator()
        let store = CandidateStore(generator: gen, orca: orca)
        let t1 = Task { await store.refresh(force: false) }     // E:p 시작 후 대기
        while !gen.isWaiting("E:p") { await Task.yield() }
        let t2 = Task { await store.refresh(force: false) }     // E:p 재요청 → inFlight → 즉시 반환
        _ = await t2.value
        XCTAssertEqual(gen.callCount, 1)
        gen.release("E:p"); _ = await t1.value
    }

    /// 배경 완료: A 생성이 끝났을 때 포커스가 이미 B면, A 결과로 화면을 덮지 않는다(캐시엔 남음).
    func testBackgroundCompletionDoesNotClobberFocusedPane() async {
        let orca = MockOrca(); orca.info = pane("A:1", answer: "aa", project: "pa", prompt: "pa")
        let gen = ControllableGenerator()
        let store = CandidateStore(generator: gen, orca: orca)
        let t1 = Task { await store.refresh(force: false) }     // E:pa + A:aa 시작
        while !(gen.isWaiting("E:pa") && gen.isWaiting("A:aa")) { await Task.yield() }
        orca.info = pane("B:1", answer: "bb", project: "pb", prompt: "pb")   // 포커스 B로 이동
        gen.release("E:pa"); gen.release("A:aa")                             // A는 배경에서 완료
        _ = await t1.value
        XCTAssertEqual(store.cachedCandidates(forPane: "A:1")?.map { $0.text }.sorted(),
                       ["gen:A:aa", "gen:E:pa"])
        XCTAssertNotEqual(store.candidates.map { $0.text }, ["gen:E:pa", "gen:A:aa"])
    }

    /// early 3개가 뜬 뒤 answer가 아직 생성 중이면 appendingMore=true(아래 '더 생성 중' 표시), 전체 스피너는 아님.
    func testAppendingMoreWhileAnswerGenerates() async {
        let orca = MockOrca(); orca.info = pane("p:1", answer: "A1")
        let gen = ControllableGenerator()
        gen.responses = ["E:p": [Candidate(text: "e1"), Candidate(text: "e2"), Candidate(text: "e3")],
                         "A:A1": [Candidate(text: "a1")]]
        let store = CandidateStore(generator: gen, orca: orca)
        let t1 = Task { await store.refresh(force: false) }         // E:p + A:A1 시작
        while !(gen.isWaiting("E:p") && gen.isWaiting("A:A1")) { await Task.yield() }
        gen.release("E:p")                                          // early 완료 → 3개 표시, answer는 아직
        while store.candidates.isEmpty { await Task.yield() }
        XCTAssertEqual(store.candidates.map { $0.text }, ["e1", "e2", "e3"])
        XCTAssertTrue(store.appendingMore)
        XCTAssertFalse(store.isRefreshing)
        gen.release("A:A1"); _ = await t1.value
        XCTAssertFalse(store.appendingMore)                        // 다 끝나면 꺼짐
        XCTAssertEqual(store.candidates.map { $0.text }, ["e1", "e2", "e3", "a1"])
    }

    /// A→B→A 왕복 후에도 A의 early 후보가 캐시에서 즉시 복원돼 화면에 남는다.
    func testEarlyDisplaySurvivesRoundTrip() async {
        let gen = MockGenerator()
        let orca = MockOrca(); orca.info = pane("A:1", answer: "", state: "working", prompt: "pa")
        let store = CandidateStore(generator: gen, orca: orca)
        await store.refresh(force: false)                                        // A early
        XCTAssertEqual(store.candidates.map { $0.text }, ["E1", "E2", "E3"])
        orca.info = pane("B:1", answer: "", state: "working", prompt: "pb")
        await store.refresh(force: false)                                        // B early
        orca.info = pane("A:1", answer: "", state: "working", prompt: "pa")
        await store.refresh(force: false)                                        // A 복귀 → 캐시 복원
        XCTAssertEqual(store.candidates.map { $0.text }, ["E1", "E2", "E3"])
    }
}
