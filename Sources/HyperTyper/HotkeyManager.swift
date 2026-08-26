import AppKit
import Carbon.HIToolbox

/// ⌘⌥1~5 전역 핫키 등록. 눌리면 해당 슬롯 번호(1~5)로 콜백한다.
/// Carbon RegisterEventHotKey는 접근성 권한 없이 앱 전역 핫키를 잡는 표준 경로다
/// (텍스트 주입만 접근성 권한을 요구하고, 핫키 감지 자체는 요구하지 않음).
/// ⌘1~5는 터미널 탭 전환과 충돌하므로 ⌘⌥ 조합을 쓴다.
final class HotkeyManager {
    private let onPress: (Int) -> Void
    private var refs: [EventHotKeyRef?] = []
    private let signature: OSType = 0x48545950 // 'HTYP'

    // ⌘⌥1~5 의 가상 키코드.
    private let keyCodes: [UInt32] = [
        UInt32(kVK_ANSI_1), UInt32(kVK_ANSI_2), UInt32(kVK_ANSI_3),
        UInt32(kVK_ANSI_4), UInt32(kVK_ANSI_5),
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
            Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue().onPress(Int(hkID.id))
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        htLog("HOTKEY installHandler status=\(hStatus)")

        let mods = UInt32(cmdKey | optionKey)
        for (i, code) in keyCodes.enumerated() {
            let id = EventHotKeyID(signature: signature, id: UInt32(i + 1))
            var ref: EventHotKeyRef?
            let st = RegisterEventHotKey(code, mods, id, GetApplicationEventTarget(), 0, &ref)
            htLog("HOTKEY register ⌘⌥\(i + 1) code=\(code) status=\(st) ref=\(ref != nil)")
            refs.append(ref)
        }
    }

    func unregister() {
        refs.compactMap { $0 }.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
    }

    deinit { unregister() }
}
