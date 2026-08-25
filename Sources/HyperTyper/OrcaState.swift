import Foundation

/// 포커스된 Orca pane과 그 세션 정보.
struct PaneInfo {
    let paneKey: String
    let cwd: String
    let project: String
    let state: String
    let userPrompt: String?
    let assistantAnswer: String?
}

/// Orca 로컬 상태 파일에서 '지금 포커스된 pane'과 그 세션을 읽는다.
/// - profiles/<active>/orca-data.json: workspaceSession.activeTabId + terminalLayoutsByTabId[tab].activeLeafId → paneKey
/// - agent-hooks/last-status.json: entries[paneKey] → cwd/state/prompt/lastAssistantMessage
/// (Orca 내부 포맷 의존 — 버전이 바뀌면 이 어댑터만 교체하면 된다.)
final class OrcaState {
    private let support: URL

    init() {
        support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Orca", isDirectory: true)
    }

    /// 감시 대상 디렉터리(포커스 전환·턴 이벤트가 여기 파일을 갱신한다).
    var profilesDir: String { support.appendingPathComponent("profiles").path }
    var agentHooksDir: String { support.appendingPathComponent("agent-hooks").path }

    func focusedPaneInfo() -> PaneInfo? {
        guard let key = focusedPaneKey() else { return nil }
        return paneInfo(for: key)
    }

    private func activeProfileDir() -> URL {
        let index = json(support.appendingPathComponent("orca-profile-index.json"))
        let id = (index?["activeProfileId"] as? String) ?? "local-default"
        return support.appendingPathComponent("profiles/\(id)", isDirectory: true)
    }

    private func focusedPaneKey() -> String? {
        let dataURL = activeProfileDir().appendingPathComponent("orca-data.json")
        guard let root = json(dataURL),
              let ws = root["workspaceSession"] as? [String: Any],
              let tab = ws["activeTabId"] as? String,
              let layouts = ws["terminalLayoutsByTabId"] as? [String: Any],
              let layout = layouts[tab] as? [String: Any],
              let leaf = layout["activeLeafId"] as? String else { return nil }
        return "\(tab):\(leaf)"
    }

    private func paneInfo(for paneKey: String) -> PaneInfo? {
        let statusURL = support.appendingPathComponent("agent-hooks/last-status.json")
        guard let root = json(statusURL),
              let entries = root["entries"] as? [String: Any],
              let entry = entries[paneKey] as? [String: Any] else { return nil }
        let payload = entry["payload"] as? [String: Any]
        let worktree = (entry["worktreeId"] as? String) ?? ""
        let cwd = worktree.components(separatedBy: "::").last ?? worktree
        return PaneInfo(
            paneKey: paneKey,
            cwd: cwd,
            project: (cwd as NSString).lastPathComponent,
            state: (payload?["state"] as? String) ?? "",
            userPrompt: payload?["prompt"] as? String,
            assistantAnswer: payload?["lastAssistantMessage"] as? String
        )
    }

    private func json(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
