import AppKit
import Carbon.HIToolbox
import Combine

/// 핫키의 '기본 조합'(modifier 집합)을 한 곳에서 관리한다.
/// 이 조합 하나가 모든 숫자 슬롯(1~6 후보, 0·7·8·9 고정문구, numpad 포함)에 "조합 + 숫자"로 적용된다.
/// 사용자가 환경설정에서 조합만 바꾸면 전 슬롯이 그 조합으로 재등록된다. UserDefaults에 저장.
@MainActor
final class HotkeySettings: ObservableObject {
    /// 지원하는 modifier(디바이스 독립 플래그만).
    static let allowed: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
    /// 기본값 = Hyper(⌃⌥⌘) — ⌘·⌘⌥+숫자는 Orca가 선점하므로.
    static let defaultMods: NSEvent.ModifierFlags = [.control, .option, .command]

    @Published var modifiers: NSEvent.ModifierFlags {
        didSet {
            UserDefaults.standard.set(Int(modifiers.rawValue), forKey: "hyper.hotkeyMods")
            onChange?()
        }
    }

    /// 조합이 바뀌면 핫키를 재등록하도록 AppDelegate가 연결한다.
    var onChange: (() -> Void)?

    init() {
        if let raw = UserDefaults.standard.object(forKey: "hyper.hotkeyMods") as? Int {
            let m = NSEvent.ModifierFlags(rawValue: UInt(raw)).intersection(Self.allowed)
            modifiers = m.isEmpty ? Self.defaultMods : m
        } else {
            modifiers = Self.defaultMods
        }
    }

    /// 특정 modifier on/off. 마지막 하나를 끄려 하면 무시한다(빈 조합이면 어떤 숫자도 못 잡으므로).
    func toggle(_ flag: NSEvent.ModifierFlags) {
        if modifiers.contains(flag) {
            let next = modifiers.subtracting(flag)
            if next.isEmpty { return }
            modifiers = next
        } else {
            modifiers = modifiers.union(flag).intersection(Self.allowed)
        }
    }

    /// 녹화로 조합을 통째 지정(빈 조합은 무시).
    func set(_ flags: NSEvent.ModifierFlags) {
        let m = flags.intersection(Self.allowed)
        guard !m.isEmpty else { return }
        modifiers = m
    }

    /// Carbon `RegisterEventHotKey`용 modifier mask.
    var carbonMask: UInt32 {
        var m: UInt32 = 0
        if modifiers.contains(.command) { m |= UInt32(cmdKey) }
        if modifiers.contains(.option) { m |= UInt32(optionKey) }
        if modifiers.contains(.control) { m |= UInt32(controlKey) }
        if modifiers.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    /// Orca가 선점해 잘 안 먹는 조합(⌘만 / ⌘⌥만)인지 — 설정 UI에서 경고를 띄우는 데 쓴다.
    var conflictsWithOrca: Bool {
        modifiers == [.command] || modifiers == [.command, .option]
    }

    /// "⌃⌥⇧⌘" 표기(macOS 표준 순서).
    var display: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s
    }
}
