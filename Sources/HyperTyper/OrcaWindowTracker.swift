import AppKit

/// 포커스된(=입력 중인) Orca 창을 추적해 프레임 + window number를 콜백한다.
/// Orca가 최상위 앱일 때만, z-order 최전면 Orca 창을 고른다(가장 큰 창 아님 → 점프 방지).
final class OrcaWindowTracker {
    private let onFrame: (CGRect, Int) -> Void
    private var timer: Timer?
    private let orcaBundleID = "com.stablyai.orca"

    init(onFrame: @escaping (CGRect, Int) -> Void) {
        self.onFrame = onFrame
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.tick()
        }
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        // Orca가 최상위 앱일 때만 추적 — 다른 앱을 쓸 땐 패널을 건드리지 않는다.
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == orcaBundleID else { return }
        guard let (frame, id) = frontmostOrcaWindow() else { return }
        onFrame(frame, id)
    }

    /// z-order 상 가장 앞(=포커스)인 Orca 메인 창의 프레임(Cocoa 좌표)과 window number.
    private func frontmostOrcaWindow() -> (CGRect, Int)? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        // CGWindowList는 앞→뒤 순서. 첫 매칭 Orca 창이 최전면.
        for w in infoList {
            guard (w[kCGWindowOwnerName as String] as? String) == "Orca",
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let width = b["Width"], let height = b["Height"],
                  width >= 400, height >= 300, // 작은 팝오버/상태창 제외
                  let number = w[kCGWindowNumber as String] as? Int else { continue }
            return (cocoaFrame(cgX: x, cgY: y, width: width, height: height), number)
        }
        return nil
    }

    /// CGWindow bounds(주 디스플레이 좌상단 원점) → Cocoa 좌하단 원점.
    private func cocoaFrame(cgX: CGFloat, cgY: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main
        let primaryHeight = primary?.frame.height ?? 0
        return CGRect(x: cgX, y: primaryHeight - cgY - height, width: width, height: height)
    }
}
