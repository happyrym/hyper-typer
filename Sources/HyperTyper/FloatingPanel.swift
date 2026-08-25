import AppKit
import SwiftUI

/// Orca 위에 떠 있는 non-activating 플로팅 패널. 포커스를 뺏지 않는다.
/// 포커스된 Orca 창을 따라가되, 사용자가 드래그해 정한 '창 기준 상대 위치(offset)'와 크기를 기억한다.
final class FloatingPanel: NSPanel {
    private var offset: CGPoint?          // panel.origin - 창 우하단(br)
    private var currentBR: CGPoint?       // 현재 추적 중인 창의 우하단
    private var isProgrammaticMove = false

    // 크기·상대 위치 저장 키(앱 재실행에도 유지).
    private let kW = "hyper.panel.width", kH = "hyper.panel.height"
    private let kOX = "hyper.panel.offsetX", kOY = "hyper.panel.offsetY"

    init<Content: View>(view: Content) {
        // 저장된 크기 복원(없으면 기본).
        let d = UserDefaults.standard
        let savedW = d.double(forKey: kW), savedH = d.double(forKey: kH)
        let w = savedW >= 240 ? savedW : 380
        let h = savedH >= 140 ? savedH : 300

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
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

        // 저장된 상대 위치 복원.
        if d.object(forKey: kOX) != nil {
            offset = CGPoint(x: d.double(forKey: kOX), y: d.double(forKey: kOY))
        }

        // 사용자가 드래그로 옮기거나 크기를 바꾸면 저장(프로그램 이동은 제외).
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(userMoved), name: NSWindow.didMoveNotification, object: self)
        nc.addObserver(self, selector: #selector(userResized), name: NSWindow.didResizeNotification, object: self)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// 포커스된 Orca 창을 따라간다. 창이 바뀌든 움직이든 항상 '창 우하단 + offset'에 위치.
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
        let o = CGPoint(x: frame.origin.x - br.x, y: frame.origin.y - br.y)
        offset = o
        UserDefaults.standard.set(Double(o.x), forKey: kOX)
        UserDefaults.standard.set(Double(o.y), forKey: kOY)
    }

    @objc private func userResized() {
        UserDefaults.standard.set(Double(frame.width), forKey: kW)
        UserDefaults.standard.set(Double(frame.height), forKey: kH)
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
