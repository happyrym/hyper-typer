import Combine
import Foundation

/// 핫키(조합 + 0·7·8·9)로 바로 주입하는 고정 문구. 조합은 HotkeySettings가 정한다.
/// 환경설정 창에서 편집하고 UserDefaults에 저장한다.
/// 0·9는 기본값이 있고, 7·8은 기본 빈칸(비우면 해당 키는 동작하지 않음).
@MainActor
final class PinStore: ObservableObject {
    @Published var slot0: String { didSet { UserDefaults.standard.set(slot0, forKey: "hyper.pin0") } }
    @Published var slot7: String { didSet { UserDefaults.standard.set(slot7, forKey: "hyper.pin7") } }
    @Published var slot8: String { didSet { UserDefaults.standard.set(slot8, forKey: "hyper.pin8") } }
    @Published var slot9: String { didSet { UserDefaults.standard.set(slot9, forKey: "hyper.pin9") } }

    init() {
        let d = UserDefaults.standard
        slot0 = d.string(forKey: "hyper.pin0") ?? "deck으로 정리"
        slot7 = d.string(forKey: "hyper.pin7") ?? ""
        slot8 = d.string(forKey: "hyper.pin8") ?? ""
        slot9 = d.string(forKey: "hyper.pin9") ?? "1pager로 정리"
    }

    /// 숫자 키(0·7·8·9)에 대응하는 고정 문구. 그 외 숫자는 고정 문구가 아니므로 nil.
    func text(forNumber n: Int) -> String? {
        switch n {
        case 0: return slot0
        case 7: return slot7
        case 8: return slot8
        case 9: return slot9
        default: return nil
        }
    }
}
