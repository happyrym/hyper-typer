import XCTest
import AppKit
import Carbon.HIToolbox
@testable import HyperTyper

/// 핫키 '기본 조합' 설정 로직 테스트 — 기본값·토글·통짜 지정·Carbon 변환·표기·영속성.
/// UserDefaults.standard의 "hyper.hotkeyMods" 키를 setUp/tearDown에서 비워 테스트 간 오염을 막는다.
@MainActor
final class HotkeySettingsTests: XCTestCase {
    private let key = "hyper.hotkeyMods"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: key)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        super.tearDown()
    }

    func testDefaultIsHyper() {
        let s = HotkeySettings()
        XCTAssertEqual(s.modifiers, [.control, .option, .command])
        XCTAssertFalse(s.modifiers.contains(.shift))
    }

    func testCarbonMaskMapsAllModifiers() {
        let s = HotkeySettings()
        s.set([.control, .option, .shift, .command])
        let expected = UInt32(cmdKey | optionKey | controlKey | shiftKey)
        XCTAssertEqual(s.carbonMask, expected)
    }

    func testCarbonMaskDefault() {
        let s = HotkeySettings()
        XCTAssertEqual(s.carbonMask, UInt32(cmdKey | optionKey | controlKey))
    }

    func testDisplayUsesStandardOrder() {
        let s = HotkeySettings()
        s.set([.command, .control, .shift, .option]) // 입력 순서 무관
        XCTAssertEqual(s.display, "⌃⌥⇧⌘")
    }

    func testToggleAddsAndRemoves() {
        let s = HotkeySettings()
        s.set([.control, .command])
        s.toggle(.shift)
        XCTAssertTrue(s.modifiers.contains(.shift))
        s.toggle(.shift)
        XCTAssertFalse(s.modifiers.contains(.shift))
    }

    func testToggleKeepsAtLeastOneModifier() {
        let s = HotkeySettings()
        s.set([.command])
        s.toggle(.command) // 마지막 하나 제거 시도는 무시되어야 한다.
        XCTAssertEqual(s.modifiers, [.command])
    }

    func testSetIgnoresEmpty() {
        let s = HotkeySettings()
        s.set([.control, .option])
        s.set([]) // 빈 조합은 무시 → 이전 값 유지
        XCTAssertEqual(s.modifiers, [.control, .option])
    }

    func testSetStripsUnsupportedFlags() {
        let s = HotkeySettings()
        s.set([.command, .capsLock, .function])
        XCTAssertEqual(s.modifiers, [.command])
    }

    func testChangePersistsAcrossInstances() {
        let s1 = HotkeySettings()
        s1.set([.control, .shift])
        let s2 = HotkeySettings()
        XCTAssertEqual(s2.modifiers, [.control, .shift])
    }

    func testInvalidSavedValueFallsBackToDefault() {
        UserDefaults.standard.set(Int(NSEvent.ModifierFlags.capsLock.rawValue), forKey: key)
        let s = HotkeySettings()
        XCTAssertEqual(s.modifiers, HotkeySettings.defaultMods)
    }

    func testOnChangeFiresOnMutation() {
        let s = HotkeySettings()
        var fired = 0
        s.onChange = { fired += 1 }
        s.toggle(.shift)
        s.set([.command])
        XCTAssertEqual(fired, 2)
    }

    func testOnChangeNotFiredWhenSetIgnored() {
        let s = HotkeySettings()
        var fired = 0
        s.onChange = { fired += 1 }
        s.set([]) // 무시 → onChange 없음
        XCTAssertEqual(fired, 0)
    }

    func testToggleNonAllowedFlagIsNoOp() {
        let s = HotkeySettings()
        s.set([.command])
        s.toggle(.capsLock) // 지원 안 하는 플래그 → 아무 변화 없음
        XCTAssertEqual(s.modifiers, [.command])
    }

    func testDisplaySingleModifier() {
        let s = HotkeySettings()
        s.set([.command])
        XCTAssertEqual(s.display, "⌘")
    }

    func testConflictsWithOrca() {
        let s = HotkeySettings()
        s.set([.command]);            XCTAssertTrue(s.conflictsWithOrca)
        s.set([.command, .option]);   XCTAssertTrue(s.conflictsWithOrca)
        s.set([.control, .option, .command]); XCTAssertFalse(s.conflictsWithOrca) // Hyper 기본값
        s.set([.control]);            XCTAssertFalse(s.conflictsWithOrca)
    }
}
