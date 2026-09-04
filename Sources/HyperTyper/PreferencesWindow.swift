import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 환경설정 창 — (1) 핫키 기본 조합 설정, (2) 고정 문구(0·7·8·9) 편집.
/// LSUIElement(.accessory) 앱이라 열 때 잠깐 활성화해 키 입력을 받는다.
/// 창이 닫힐 때 녹화가 진행 중이면 정리하도록 NSWindowDelegate를 겸한다.
@MainActor
final class PreferencesWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let pins: PinStore
    private let hotkeys: HotkeySettings
    private let recorder: HotkeyRecorder

    init(pins: PinStore,
         hotkeys: HotkeySettings,
         onRecordStart: @escaping () -> Void,
         onRecordEnd: @escaping () -> Void) {
        self.pins = pins
        self.hotkeys = hotkeys
        self.recorder = HotkeyRecorder(settings: hotkeys, onStart: onRecordStart, onEnd: onRecordEnd)
        super.init()
    }

    func show() {
        if window == nil {
            let root = PreferencesView(pins: pins, hotkeys: hotkeys, recorder: recorder)
            let hosting = NSHostingController(rootView: root)
            let w = NSWindow(contentViewController: hosting)
            w.title = "하이퍼 타이퍼 설정"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.delegate = self
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        recorder.stop()
    }

    /// 녹화 중 다른 앱으로 전환하면 keyDown이 더는 도달하지 않는다.
    /// 그대로 두면 전역 핫키가 해제된 채(suspend) 방치되므로, 녹화를 끝내 복구한다.
    func windowDidResignKey(_ notification: Notification) {
        recorder.stop()
    }
}

/// 키 조합 직접 녹화 — 사용자가 원하는 modifier들을 누른 채 아무 키나 누르면 그 조합을 잡는다.
/// 녹화 동안엔 현재 전역 핫키를 임시 해제(onStart)해 입력을 가로채지 않게 하고, 끝나면 복구(onEnd)한다.
/// Esc(keyCode 53)로 취소. 로컬 이벤트 모니터는 stop/deinit에서 반드시 제거한다.
@MainActor
final class HotkeyRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    private var monitor: Any?
    private let settings: HotkeySettings
    private let onStart: () -> Void
    private let onEnd: () -> Void

    init(settings: HotkeySettings, onStart: @escaping () -> Void, onEnd: @escaping () -> Void) {
        self.settings = settings
        self.onStart = onStart
        self.onEnd = onEnd
    }

    func toggle() { isRecording ? stop() : start() }

    private func start() {
        guard !isRecording else { return }
        isRecording = true
        onStart()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == UInt16(kVK_Escape) {
                self.stop()
                return nil
            }
            let mods = event.modifierFlags.intersection(HotkeySettings.allowed)
            if !mods.isEmpty {
                self.settings.set(mods)
                self.stop()
            }
            return nil // 녹화 중 키 입력은 삼켜서 다른 곳으로 새지 않게 한다.
        }
    }

    func stop() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
        if isRecording {
            isRecording = false
            onEnd()
        }
    }

    deinit {
        if let m = monitor { NSEvent.removeMonitor(m) }
    }
}

private struct PreferencesView: View {
    @ObservedObject var pins: PinStore
    @ObservedObject var hotkeys: HotkeySettings
    @ObservedObject var recorder: HotkeyRecorder

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            comboSection
            Divider()
            pinsSection
            Text("핫키로 텍스트를 주입하려면 손쉬운 사용(접근성) 권한이 필요합니다 — 메뉴바 ✨ › 손쉬운 사용 권한 열기.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("완료") { NSApp.keyWindow?.close() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 420)
    }

    // MARK: 핫키 기본 조합

    private var comboSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("단축키 조합")
                .font(.system(size: 13, weight: .semibold))
            Text("현재: \(hotkeys.display) + 숫자   (예: \(hotkeys.display)1 → 후보 1)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                modToggle("⌃", "Control", .control)
                modToggle("⌥", "Option", .option)
                modToggle("⇧", "Shift", .shift)
                modToggle("⌘", "Command", .command)
                Button(recorder.isRecording ? "누르는 중… (Esc 취소)" : "직접 지정") {
                    recorder.toggle()
                }
                .buttonStyle(.bordered)
            }
            // 녹화는 keyDown 시점의 modifier만 잡으므로, 조합을 누른 채 아무 키나 눌러야 확정된다.
            if recorder.isRecording {
                Text("원하는 조합을 누른 채 아무 키나 눌러 확정하세요.")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
            if hotkeys.conflictsWithOrca {
                Text("⚠️ ⌘·⌘⌥+숫자는 Orca가 선점해 안 먹을 수 있어요. ⌃·⌥·⇧를 더한 조합을 권장합니다.")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
            Text("바꾸면 모든 숫자(1~6 후보 · 0·7·8·9 고정문구 · 우측 numpad)에 즉시·자동 저장 적용됩니다.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    /// modifier 토글 한 칸. 녹화 중에는 비활성화한다(녹화 중 조합을 바꾸면 흐름이 헷갈리므로).
    private func modToggle(_ glyph: String, _ name: String, _ flag: NSEvent.ModifierFlags) -> some View {
        let on = hotkeys.modifiers.contains(flag)
        return Text(glyph)
            .font(.system(size: 14))
            .frame(width: 40, height: 28)
            .background(on ? Color.accentColor : Color.gray.opacity(0.15))
            .foregroundStyle(on ? Color.white : Color.primary)
            .opacity(recorder.isRecording ? 0.4 : 1)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onTapGesture { if !recorder.isRecording { hotkeys.toggle(flag) } }
            .accessibilityLabel(name)
            .accessibilityValue(on ? "켜짐" : "꺼짐")
            .accessibilityAddTraits(.isButton)
    }

    // MARK: 고정 문구

    private var pinsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("고정 문구 — 비우면 그 키는 동작하지 않습니다.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            field("\(hotkeys.display)0", text: $pins.slot0)
            field("\(hotkeys.display)7", text: $pins.slot7)
            field("\(hotkeys.display)8", text: $pins.slot8)
            field("\(hotkeys.display)9", text: $pins.slot9)
        }
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 64, alignment: .leading)
            TextField("문구", text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
}
