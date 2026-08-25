import AppKit
import SwiftUI

/// Orca 위에 떠 있는 non-activating 플로팅 패널. 포커스를 뺏지 않는다.
/// 포커스된 Orca 창을 따라가되, 사용자가 드래그해 정한 '창 기준 상대 위치(offset)'를 유지한다.
final class FloatingPanel: NSPanel {
    private var offset: CGPoint?          // panel.origin - 창 우하단(br)
    private var currentBR: CGPoint?       // 현재 추적 중인 창의 우하단
    private var isProgrammaticMove = false

    init<Content: View>(view: Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        contentView = NSHostingView(rootView: view)
        center()

        // 사용자가 드래그로 옮기면 offset을 갱신한다(프로그램 이동은 제외).
        NotificationCenter.default.addObserver(
            self, selector: #selector(userMoved), name: NSWindow.didMoveNotification, object: self)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// 포커스된 Orca 창을 따라간다. 창이 바뀌든 움직이든 항상 '창 우하단 + offset'에 위치.
    /// offset은 사용자가 드래그로 정하며, 없으면 기본(우하단 안쪽)을 쓴다.
    func follow(orcaFrame: CGRect, windowID: Int) {
        let br = CGPoint(x: orcaFrame.maxX, y: orcaFrame.minY)
        currentBR = br
        let off = offset ?? CGPoint(x: -frame.width - 16, y: 16)
        if offset == nil { offset = off }
        let origin = clamped(CGPoint(x: br.x + off.x, y: br.y + off.y))

        isProgrammaticMove = true
        setFrameOrigin(origin)
        DispatchQueue.main.async { self.isProgrammaticMove = false }
    }

    @objc private func userMoved() {
        guard !isProgrammaticMove, let br = currentBR else { return }
        offset = CGPoint(x: frame.origin.x - br.x, y: frame.origin.y - br.y)
    }

    /// 계산 위치가 모든 화면 밖이면 주 화면 안으로 당긴다(듀얼 모니터 안전장치).
    private func clamped(_ origin: CGPoint) -> CGPoint {
        let rect = CGRect(x: origin.x, y: origin.y, width: frame.width, height: frame.height)
        if NSScreen.screens.contains(where: { $0.frame.intersects(rect) }) { return origin }
        guard let vf = NSScreen.main?.visibleFrame else { return origin }
        return CGPoint(x: min(max(origin.x, vf.minX), vf.maxX - frame.width),
                       y: min(max(origin.y, vf.minY), vf.maxY - frame.height))
    }
}
