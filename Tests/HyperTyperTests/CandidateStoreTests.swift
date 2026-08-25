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

private func pane(_ key: String, prompt: String, project: String = "proj") -> PaneInfo {
    PaneInfo(paneKey: key, cwd: "/x/\(project)", project: project,
             state: "done", userPrompt: prompt, assistantAnswer: "ans")
}

@MainActor
final class CandidateStoreTests: XCTestCase {

    func testGeneratesOnFirstResolve() async {
        let gen = MockGenerator(response: [Candidate(text: "a")])
        let orca = MockOrca(); orca.info = pane("p:1", prompt: "hello")
        let store = CandidateStore(generator: gen, orca: orca)
        await store.refresh(force: false)
        XCTAssertEqual(gen.callCount, 1)
        XCTAssertEqual(store.candidates.map { $0.text }, ["a"])
    }

    func testCacheHitAvoidsRegeneration() async {
        let gen = MockGenerator()
        let orca = MockOrca(); orca.info = pane("p:1", prompt: "hello")
        let store = CandidateStore(generator: gen, orca: orca)
        await store.refresh(force: false)
        await store.refresh(force: false)   // 같은 pane+프롬프트 → 캐시 적중, 재생성 없음
        XCTAssertEqual(gen.callCount, 1)
    }

    func testPromptChangeRegenerates() async {
        let gen = MockGenerator()
        let orca = MockOrca(); orca.info = pane("p:1", prompt: "hello")
        let store = CandidateStore(generator: gen, orca: orca)
        await store.refresh(force: false)
        orca.info = pane("p:1", prompt: "world")   // 같은 pane, 새 프롬프트(=새 제출)
        await store.refresh(force: false)
        XCTAssertEqual(gen.callCount, 2)
    }

    /// 터미널별 캐시 격리 — A→B→A 왕복 시 A는 캐시 적중(핵심 UX).
    func testPerPaneCacheIsolation() async {
        let gen = MockGenerator()
        let orca = MockOrca(); orca.info = pane("A:1", prompt: "pa")
        let store = CandidateStore(generator: gen, orca: orca)
        await store.refresh(force: false)          // A 생성 (1)
        orca.info = pane("B:1", prompt: "pb")
        await store.refresh(force: false)          // B 생성 (2)
        orca.info = pane("A:1", prompt: "pa")
        await store.refresh(force: false)          // A로 복귀 → 캐시 적중 (여전히 2)
        XCTAssertEqual(gen.callCount, 2)
    }

    func testForceAlwaysRegenerates() async {
        let gen = MockGenerator()
        let orca = MockOrca(); orca.info = pane("p:1", prompt: "hello")
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
}
