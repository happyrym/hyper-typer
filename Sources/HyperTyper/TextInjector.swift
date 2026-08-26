import AppKit

/// 포커스된 앱(Orca)에 텍스트를 직접 타이핑한다. 클립보드를 거치지 않아 사용자 클립보드를 오염시키지 않는다.
/// 합성 키 이벤트라 접근성(Accessibility) 권한이 필요하며, 없으면 조용히 무효가 된다.
enum TextInjector {
    /// 접근성 권한 여부(필요 시 시스템 설정 프롬프트 표시).
    @discardableResult
    static func ensureTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    static func inject(_ text: String) {
        let trusted = AXIsProcessTrusted()
        htLog("INJECT trusted=\(trusted) len=\(text.count)")
        guard !text.isEmpty, trusted else { return }

        // ⌘⌥ 가 아직 눌려 있으면 주입 문자에 modifier가 섞여 문자가 아닌 단축키로 해석된다.
        // 약간 지연해 release 여지를 주고, 이벤트의 flags를 비워 modifier 오염을 제거한다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            let source = CGEventSource(stateID: .combinedSessionState)
            var utf16 = Array(text.utf16)

            let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            down?.flags = []
            down?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            down?.post(tap: .cghidEventTap)

            let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            up?.flags = []
            up?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            up?.post(tap: .cghidEventTap)
        }
    }
}
