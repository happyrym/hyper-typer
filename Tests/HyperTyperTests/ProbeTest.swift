import XCTest
@testable import HyperTyper

private final class MockOrca2: FocusResolving, @unchecked Sendable {
    var info: PaneInfo?
    func focusedPaneInfo() -> PaneInfo? { info }
}

// Generator that blocks the first caller until released, and can mutate orca focus.
private final class GateGenerator: CandidateGenerating, @unchecked Sendable {
    let orca: MockOrca2
    let sem = DispatchSemaphore(value: 0)   // caller waits here
    let entered = DispatchSemaphore(value: 0)
    var mutateTo: PaneInfo?
    var response: [Candidate]
    init(orca: MockOrca2, response: [Candidate]) { self.orca = orca; self.response = response }
    func generate(from exchange: Exchange) async -> [Candidate] {
        entered.signal()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async { self.sem.wait(); c.resume() }
        }
        if let m = mutateTo { orca.info = m }
        return response
    }
}

private func pane(_ key: String, answer: String, state: String = "done", project: String = "proj") -> PaneInfo {
    PaneInfo(paneKey: key, cwd: "/x/\(project)", project: project, state: state, userPrompt: "p", assistantAnswer: answer)
}

@MainActor
final class ProbeTests: XCTestCase {
    // Two concurrent same-genKey Tasks; during generate, focus moves to a DIFFERENT pane B
    // that is NOT in cache and requires generation. Then no further events fire.
    func testTwoTaskStuckSpinner() async {
        let orca = MockOrca2(); orca.info = pane("p:1", answer: "A2")
        let gen = GateGenerator(orca: orca, response: [Candidate(text: "p-result")])
        // when generate finishes, focus is already on B (different pane, no cache)
        gen.mutateTo = pane("B:1", answer: "bb")
        let store = CandidateStore(generator: gen, orca: orca)

        // Task1 enters generate and blocks
        let t1 = Task { await store.refresh(force: false) }
        gen.entered.wait()   // Task1 is now suspended inside generate

        // Task2: same pane+answer, hits inFlight early-return
        await store.refresh(force: false)   // returns immediately at inFlight.contains

        // release Task1 -> it resumes, mutates focus to B, guard fails (B != p)
        gen.sem.signal()
        _ = await t1.value

        // No further events fire. Observe resting state.
        print("PROBE isRefreshing=\(store.isRefreshing) candidates=\(store.candidates.map{$0.text}) cacheP=\(store.cachedCandidates(forPane: "p:1")?.map{$0.text} ?? []) cacheB=\(store.cachedCandidates(forPane: "B:1")?.map{$0.text} ?? [])")
    }
}
