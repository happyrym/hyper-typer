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
}
