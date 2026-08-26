import AppKit
import SwiftUI

/// 고정 문구(⌃⌥⌘ 0·7·8·9) 편집 창. LSUIElement(.accessory) 앱이라 열 때 잠깐 활성화해 키 입력을 받는다.
@MainActor
final class PreferencesWindowController {
    private var window: NSWindow?
    private let pins: PinStore

    init(pins: PinStore) { self.pins = pins }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: PinsEditorView(pins: pins))
            let w = NSWindow(contentViewController: hosting)
            w.title = "고정 문구 편집"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct PinsEditorView: View {
    @ObservedObject var pins: PinStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("핫키로 바로 주입할 고정 문구 — 비우면 그 키는 동작하지 않는다.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            field("⌃⌥⌘0", text: $pins.slot0)
            field("⌃⌥⌘7", text: $pins.slot7)
            field("⌃⌥⌘8", text: $pins.slot8)
            field("⌃⌥⌘9", text: $pins.slot9)
            HStack {
                Spacer()
                Button("완료") { NSApp.keyWindow?.close() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 52, alignment: .leading)
            TextField("문구", text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
}
