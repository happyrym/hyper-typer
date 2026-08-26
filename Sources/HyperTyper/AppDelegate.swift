import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel!
    private var tracker: OrcaWindowTracker!
    private var watcher: TranscriptWatcher!
    private var watcher2: TranscriptWatcher!
    private var statusBar: StatusBarController!
    private var hotkeys: HotkeyManager!
    private let store = CandidateStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let view = PanelView(store: store)
        panel = FloatingPanel(view: view)
        panel.orderFrontRegardless()

        // 저장된 글씨 크기 복원(앱 재실행에도 고정).
        let savedSize = UserDefaults.standard.double(forKey: "hyper.fontSize")
        if savedSize >= 11 { store.fontSize = CGFloat(savedSize) }

        // 메뉴바 아이콘(실행 표시 + 종료/새로고침/글씨 크기). 크기 변경 시 UserDefaults에 저장.
        statusBar = StatusBarController(
            currentSize: store.fontSize,
            onRefresh: { [weak self] in self?.store.refreshFromTranscript() },
            onFontSize: { [weak self] size in
                self?.store.fontSize = size
                UserDefaults.standard.set(Double(size), forKey: "hyper.fontSize")
            }
        )

        // Orca 창을 추적해 패널을 그 위에 앵커링.
        tracker = OrcaWindowTracker { [weak self] frame, windowID in
            self?.panel.follow(orcaFrame: frame, windowID: windowID)
        }
        tracker.start()

        // 로그 디렉터리.
        let htDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hyper-typer", isDirectory: true)
        try? FileManager.default.createDirectory(at: htDir, withIntermediateDirectories: true)

        // Orca 상태 감시: 포커스 전환(profiles/orca-data.json) + 턴 이벤트(agent-hooks/last-status.json).
        // 어느 쪽이 바뀌든 refreshIfChanged → 포커스 pane 해석 → pane별 캐시(전환 무지연) 또는 생성.
        let orca = OrcaState()
        watcher = TranscriptWatcher(path: orca.profilesDir) { [weak self] in
            MainActor.assumeIsolated { self?.store.refreshIfChanged() }
        }
        watcher.start()
        watcher2 = TranscriptWatcher(path: orca.agentHooksDir) { [weak self] in
            MainActor.assumeIsolated { self?.store.refreshIfChanged() }
        }
        watcher2.start()

        // ⌘⌥1~5 로 해당 슬롯 후보를 Orca에 직접 주입(클립보드 우회). 주입엔 접근성 권한 필요.
        TextInjector.ensureTrusted(prompt: true)
        hotkeys = HotkeyManager { [weak self] slot in
            MainActor.assumeIsolated {
                let text = self?.store.candidateText(at: slot - 1)
                htLog("HOTKEY press slot=\(slot) text=\"\(String((text ?? "nil").prefix(30)))\"")
                guard let text, !text.hasPrefix("⚠️") else { return }
                TextInjector.inject(text)
            }
        }
        hotkeys.register()

        // 첫 로드: 직전 assistant 턴으로 후보 생성.
        store.refreshFromTranscript()
    }

    func applicationWillTerminate(_ notification: Notification) {
        watcher?.stop()
        watcher2?.stop()
        tracker?.stop()
        hotkeys?.unregister()
    }
}
