import AppKit

/// 메뉴바(상태바) 아이콘 + 메뉴. 앱 실행 여부를 보여주고 종료·새로고침을 제공한다.
/// (에이전트 앱이라 Dock 아이콘이 없으므로 이게 유일한 조작 지점.)
@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let onRefresh: () -> Void

    init(onRefresh: @escaping () -> Void) {
        self.onRefresh = onRefresh
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Hyper Typer")
            button.image?.isTemplate = true
            button.toolTip = "하이퍼 타이퍼"
        }

        let menu = NSMenu()
        let title = NSMenuItem(title: "하이퍼 타이퍼", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        menu.addItem(item(title: "지금 후보 새로고침", key: "r", action: #selector(refresh)))
        menu.addItem(.separator())
        menu.addItem(item(title: "종료", key: "q", action: #selector(quit)))
        statusItem.menu = menu
    }

    private func item(title: String, key: String, action: Selector) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = self
        return mi
    }

    @objc private func refresh() { onRefresh() }
    @objc private func quit() { NSApp.terminate(nil) }
}
