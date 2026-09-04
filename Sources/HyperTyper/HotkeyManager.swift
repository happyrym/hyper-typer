import AppKit
import Carbon.HIToolbox

/// (조합) + 숫자 전역 핫키 등록. 눌리면 그 '숫자'(0~9)로 콜백한다.
/// 1~6은 생성된 후보 슬롯, 0·7·8·9는 고정 문구(핫키 전용)로 쓰인다.
/// modifier 조합은 HotkeySettings가 정하며(기본 Hyper ⌃⌥⌘), 조합이 바뀌면 setModifiers로 전 키를 재등록한다.
/// Carbon RegisterEventHotKey는 접근성 권한 없이 앱 전역 핫키를 잡는 표준 경로다
/// (텍스트 주입만 접근성 권한을 요구하고, 핫키 감지·재등록은 요구하지 않음 → 조합 변경에 재승인 불필요).
final class HotkeyManager {
    private let onPress: (Int) -> Void
    private var refs: [EventHotKeyRef?] = []
    private var handlerRef: EventHandlerRef?
    private var currentMods: UInt32 = 0
    // 녹화 중(suspend)에는 조합이 바뀌어도 실제 등록을 미룬다 — resume에서 최종 조합으로 한 번만 등록.
    private var suspended = false
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

    /// 핸들러 설치(1회) + 주어진 modifier로 전 키 등록. 반복 호출에도 안전하도록 먼저 해제한다.
    func register(mods: UInt32) {
        installHandlerOnce()
        currentMods = mods
        unregisterKeys()
        registerKeys()
    }

    /// 조합 변경 — 기존 키 해제 후 새 modifier로 재등록(핸들러는 유지).
    /// 녹화 중(suspended)이면 조합만 기억하고 등록은 resume까지 미룬다(녹화 입력 가로채기 방지).
    func setModifiers(_ mods: UInt32) {
        currentMods = mods
        guard !suspended else { return }
        unregisterKeys()
        registerKeys()
    }

    /// 조합 녹화 중, 현재 조합 키가 녹화 입력을 가로채지 않도록 임시 해제.
    func suspend() {
        suspended = true
        unregisterKeys()
    }
    /// 녹화 종료 시 (녹화 중 바뀌었을 수 있는) 최종 조합으로 한 번만 재등록.
    func resume() {
        suspended = false
        unregisterKeys()
        registerKeys()
    }

    private func installHandlerOnce() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: OSType(kEventHotKeyPressed))
        var ref: EventHandlerRef?
        let hStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(event, OSType(kEventParamDirectObject), OSType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            guard let userData else { return noErr }
            Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue().fire(id: Int(hkID.id))
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &ref)
        htLog("HOTKEY installHandler status=\(hStatus)")
        // 설치 실패면 ref를 남기지 않아 다음 register에서 재시도한다(핫키 조용히 죽는 것 방지).
        if hStatus == noErr { handlerRef = ref }
    }

    private func registerKeys() {
        for (i, key) in keys.enumerated() {
            let id = EventHotKeyID(signature: signature, id: UInt32(i + 1))
            var ref: EventHotKeyRef?
            let st = RegisterEventHotKey(key.code, currentMods, id, GetApplicationEventTarget(), 0, &ref)
            htLog("HOTKEY register mods=\(currentMods) num=\(key.number) code=\(key.code) status=\(st) ref=\(ref != nil)")
            refs.append(ref)
        }
    }

    private func unregisterKeys() {
        refs.compactMap { $0 }.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
    }

    private func fire(id: Int) {
        guard id >= 1, id <= keys.count else { return }
        onPress(keys[id - 1].number)
    }

    func unregister() { unregisterKeys() }

    deinit {
        unregisterKeys()
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
