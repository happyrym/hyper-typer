import AppKit

/// 메뉴바(상태바) 아이콘 + 메뉴. 실행 표시 + 종료·새로고침·글씨 크기 조정.
@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let onRefresh: () -> Void
    private let onFontSize: (CGFloat) -> Void
    private var fontItems: [NSMenuItem] = []
    private var currentSize: CGFloat

    /// 글씨 크기 5단계.
    private let sizes: [(String, CGFloat)] = [
        ("아주 작게", 11), ("작게", 12), ("보통", 13), ("크게", 15), ("아주 크게", 17),
    ]

    init(currentSize: CGFloat, onRefresh: @escaping () -> Void, onFontSize: @escaping (CGFloat) -> Void) {
        self.currentSize = currentSize
        self.onRefresh = onRefresh
        self.onFontSize = onFontSize
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
        // 글씨 크기는 서브메뉴로 접어 메뉴를 작게 유지.
        let sizeParent = NSMenuItem(title: "글씨 크기", action: nil, keyEquivalent: "")
        let sizeSubmenu = NSMenu()
        for (label, size) in sizes {
            let mi = NSMenuItem(title: "\(label) (\(Int(size)))", action: #selector(setFont(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = NSNumber(value: Double(size))
            mi.state = (size == currentSize) ? .on : .off
            fontItems.append(mi)
            sizeSubmenu.addItem(mi)
        }
        sizeParent.submenu = sizeSubmenu
        menu.addItem(sizeParent)

        menu.addItem(.separator())
        menu.addItem(item(title: "종료", key: "q", action: #selector(quit)))
        statusItem.menu = menu
    }

    private func item(title: String, key: String, action: Selector) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = self
        return mi
    }

    @objc private func setFont(_ sender: NSMenuItem) {
        guard let size = (sender.representedObject as? NSNumber).map({ CGFloat($0.doubleValue) }) else { return }
        currentSize = size
        for mi in fontItems {
            let s = (mi.representedObject as? NSNumber).map { CGFloat($0.doubleValue) }
            mi.state = (s == size) ? .on : .off
        }
        onFontSize(size)
    }

    @objc private func refresh() { onRefresh() }
    @objc private func quit() { NSApp.terminate(nil) }
}
