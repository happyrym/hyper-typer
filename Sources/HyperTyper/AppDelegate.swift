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
    private let pins = PinStore()
    private let hotkeySettings = HotkeySettings()
    private var prefs: PreferencesWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let view = PanelView(store: store)
        panel = FloatingPanel(view: view)
        panel.orderFrontRegardless()

        // 저장된 글씨 크기 복원(앱 재실행에도 고정).
        let savedSize = UserDefaults.standard.double(forKey: "hyper.fontSize")
        if savedSize >= 11 { store.fontSize = CGFloat(savedSize) }

        // 메뉴바 아이콘(실행 표시 + 종료/새로고침/글씨 크기). 크기 변경 시 UserDefaults에 저장.
        // 조합 녹화 중에는 현재 핫키가 입력을 가로채므로 onRecordStart/onRecordEnd로 임시 해제·복구한다.
        prefs = PreferencesWindowController(
            pins: pins,
            hotkeys: hotkeySettings,
            onRecordStart: { [weak self] in self?.hotkeys.suspend() },
            onRecordEnd: { [weak self] in self?.hotkeys.resume() }
        )
        statusBar = StatusBarController(
            currentSize: store.fontSize,
            onRefresh: { [weak self] in self?.store.refreshFromTranscript() },
            onFontSize: { [weak self] size in
                self?.store.fontSize = size
                UserDefaults.standard.set(Double(size), forKey: "hyper.fontSize")
            },
            onOpenPreferences: { [weak self] in self?.prefs.show() }
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

        // 조합+숫자 핫키로 해당 슬롯(1~6 후보 · 0·7·8·9 고정문구)을 Orca에 직접 주입(클립보드 우회). 주입엔 접근성 권한 필요.
        TextInjector.ensureTrusted(prompt: true)
        hotkeys = HotkeyManager { [weak self] number in
            MainActor.assumeIsolated {
                guard let self else { return }
                // 0·7·8·9는 고정 문구, 1~6은 생성된 후보 슬롯.
                let text = self.pins.text(forNumber: number) ?? self.store.candidateText(at: number - 1)
                htLog("HOTKEY press num=\(number) text=\"\(String((text ?? "nil").prefix(30)))\"")
                guard let text, !text.isEmpty, !text.hasPrefix("⚠️") else { return }
                TextInjector.inject(text)
            }
        }
        hotkeys.register(mods: hotkeySettings.carbonMask)
        // 설정에서 조합이 바뀌면 전 슬롯을 새 조합으로 재등록(핸들러는 유지 → 재승인 불필요).
        hotkeySettings.onChange = { [weak self] in
            guard let self else { return }
            self.hotkeys.setModifiers(self.hotkeySettings.carbonMask)
        }

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
