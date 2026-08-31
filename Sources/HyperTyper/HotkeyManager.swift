import AppKit
import Carbon.HIToolbox

/// ⌃⌥⌘ + 숫자 전역 핫키 등록. 눌리면 그 '숫자'(0~9)로 콜백한다.
/// 1~6은 생성된 후보 슬롯, 0·7·8·9는 고정 문구(핫키 전용)로 쓰인다.
/// Carbon RegisterEventHotKey는 접근성 권한 없이 앱 전역 핫키를 잡는 표준 경로다
/// (텍스트 주입만 접근성 권한을 요구하고, 핫키 감지 자체는 요구하지 않음).
/// ⌘·⌘⌥ + 숫자는 Orca 등이 선점해 충돌하므로, 세 모디파이어(Hyper) 조합으로 충돌을 피한다.
final class HotkeyManager {
    private let onPress: (Int) -> Void
    private var refs: [EventHotKeyRef?] = []
    private let signature: OSType = 0x48545950 // 'HTYP'

    // (가상 키코드, 대응 숫자). 등록 순서의 인덱스+1을 핫키 ID로 쓰고, ID로 이 표를 되짚어 숫자를 얻는다.
    // 상단 숫자열과 우측 numpad(Keypad*)를 같은 숫자로 함께 등록 — 어느 쪽을 눌러도 동작한다.
    private let keys: [(code: UInt32, number: Int)] = [
        (UInt32(kVK_ANSI_1), 1), (UInt32(kVK_ANSI_2), 2), (UInt32(kVK_ANSI_3), 3),
        (UInt32(kVK_ANSI_4), 4), (UInt32(kVK_ANSI_5), 5), (UInt32(kVK_ANSI_6), 6),
        (UInt32(kVK_ANSI_0), 0), (UInt32(kVK_ANSI_7), 7),
        (UInt32(kVK_ANSI_8), 8), (UInt32(kVK_ANSI_9), 9),
        (UInt32(kVK_ANSI_Keypad0), 0), (UInt32(kVK_ANSI_Keypad1), 1), (UInt32(kVK_ANSI_Keypad2), 2),
        (UInt32(kVK_ANSI_Keypad3), 3), (UInt32(kVK_ANSI_Keypad4), 4), (UInt32(kVK_ANSI_Keypad5), 5),
        (UInt32(kVK_ANSI_Keypad6), 6), (UInt32(kVK_ANSI_Keypad7), 7), (UInt32(kVK_ANSI_Keypad8), 8),
        (UInt32(kVK_ANSI_Keypad9), 9),
    ]

    init(onPress: @escaping (Int) -> Void) {
        self.onPress = onPress
    }

    func register() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: OSType(kEventHotKeyPressed))
        let hStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(event, OSType(kEventParamDirectObject), OSType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            guard let userData else { return noErr }
            Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue().fire(id: Int(hkID.id))
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        htLog("HOTKEY installHandler status=\(hStatus)")

        let mods = UInt32(cmdKey | optionKey | controlKey)
        for (i, key) in keys.enumerated() {
            let id = EventHotKeyID(signature: signature, id: UInt32(i + 1))
            var ref: EventHotKeyRef?
            let st = RegisterEventHotKey(key.code, mods, id, GetApplicationEventTarget(), 0, &ref)
            htLog("HOTKEY register ⌃⌥⌘\(key.number) code=\(key.code) status=\(st) ref=\(ref != nil)")
            refs.append(ref)
        }
    }

    private func fire(id: Int) {
        guard id >= 1, id <= keys.count else { return }
        onPress(keys[id - 1].number)
    }

    func unregister() {
        refs.compactMap { $0 }.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
    }

    deinit { unregister() }
}
