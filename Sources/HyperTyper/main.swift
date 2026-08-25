import AppKit

// 하이퍼 타이퍼 v0 — Orca 위에 떠서 다음 프롬프트 후보 5개를 보여주는 플로팅 패널.
// 에이전트 앱(.accessory): Dock 아이콘 없음, 포커스 안 뺏음.
// 최상위 코드는 메인 액터로 격리되지 않으므로 assumeIsolated로 감싼다(실제로 메인 스레드에서 실행).
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
