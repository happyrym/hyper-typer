import XCTest
@testable import HyperTyper

/// Orca 상태 파일(orca-data.json + last-status.json)에서 포커스된 pane 세션을 해석하는 로직 테스트.
/// 실제 Orca 없이 임시 디렉터리에 픽스처를 써서 검증한다.
final class OrcaStateTests: XCTestCase {
    private var support: URL!

    override func setUpWithError() throws {
        support = FileManager.default.temporaryDirectory
            .appendingPathComponent("orca-test-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: support)
    }

    private func write(_ obj: Any, to relativePath: String) throws {
        let url = support.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: obj, options: []).write(to: url)
    }

    private func makeFixture(activeTab: String, activeLeaf: String, entries: [String: Any]) throws {
        try write(["activeProfileId": "p1"], to: "orca-profile-index.json")
        try write([
            "workspaceSession": [
                "activeTabId": activeTab,
                "terminalLayoutsByTabId": [activeTab: ["activeLeafId": activeLeaf]],
            ],
        ], to: "profiles/p1/orca-data.json")
        try write(["entries": entries], to: "agent-hooks/last-status.json")
    }

    func testResolvesFocusedPane() throws {
        let paneKey = "tabA:leafA"
        try makeFixture(activeTab: "tabA", activeLeaf: "leafA", entries: [
            paneKey: [
                "worktreeId": "wid::/Users/me/proj",
                "payload": ["state": "done", "prompt": "안녕", "lastAssistantMessage": "응 안녕"],
            ],
        ])
        let info = OrcaState(support: support).focusedPaneInfo()
        XCTAssertEqual(info?.paneKey, paneKey)
        XCTAssertEqual(info?.cwd, "/Users/me/proj")
        XCTAssertEqual(info?.project, "proj")
        XCTAssertEqual(info?.state, "done")
        XCTAssertEqual(info?.userPrompt, "안녕")
        XCTAssertEqual(info?.assistantAnswer, "응 안녕")
    }

    func testFocusedPaneWithoutStatusEntryIsNil() throws {
        // 포커스 pane은 해석되지만 last-status에 항목이 없으면 nil.
        try makeFixture(activeTab: "tabX", activeLeaf: "leafX", entries: [:])
        XCTAssertNil(OrcaState(support: support).focusedPaneInfo())
    }

    func testMissingDataReturnsNil() throws {
        // 파일이 아예 없으면 크래시 없이 nil.
        XCTAssertNil(OrcaState(support: support).focusedPaneInfo())
    }

    func testFollowsFocusWhenActiveTabChanges() throws {
        // 포커스가 다른 탭으로 가면 그 탭의 세션을 해석(터미널별 스코핑의 핵심).
        try makeFixture(activeTab: "tabB", activeLeaf: "leafB", entries: [
            "tabA:leafA": ["worktreeId": "w::/a", "payload": ["prompt": "A질문", "state": "done"]],
            "tabB:leafB": ["worktreeId": "w::/b", "payload": ["prompt": "B질문", "state": "working"]],
        ])
        let info = OrcaState(support: support).focusedPaneInfo()
        XCTAssertEqual(info?.userPrompt, "B질문")
        XCTAssertEqual(info?.project, "b")
    }
}
