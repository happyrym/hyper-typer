import XCTest
@testable import HyperTyper

/// claude CLI(--output-format json) 출력 파싱 로직 테스트. CLI 호출 자체는 mock 대상이 아니라
/// 여기서는 '출력 문자열 → 후보' 순수 변환만 검증한다(네트워크/LLM 불필요).
final class CandidateGeneratorTests: XCTestCase {
    let gen = CandidateGenerator()

    /// CLI 봉투를 안전하게 만들어 주는 헬퍼(수기 이스케이프 회피).
    private func envelope(result: String, isError: Bool = false) -> String {
        let obj: [String: Any] = ["type": "result", "is_error": isError, "result": result]
        let data = try! JSONSerialization.data(withJSONObject: obj)
        return String(data: data, encoding: .utf8)!
    }

    func testParsesFiveLines() {
        let raw = envelope(result: "테스트 돌려줘\n결과 보여줘\n배포 가능한지 확인해\n코드 리뷰 해줄래\n이제 뭐 할까")
        XCTAssertEqual(gen.parseCandidates(raw),
                       ["테스트 돌려줘", "결과 보여줘", "배포 가능한지 확인해", "코드 리뷰 해줄래", "이제 뭐 할까"])
    }

    func testIsErrorReturnsNil() {
        XCTAssertNil(gen.parseCandidates(envelope(result: "무시됨", isError: true)))
    }

    func testStripsNumberingAndBullets() {
        let raw = envelope(result: "1. 첫째\n2) 둘째\n- 셋째\n* 넷째\n다섯째")
        XCTAssertEqual(gen.parseCandidates(raw), ["첫째", "둘째", "셋째", "넷째", "다섯째"])
    }

    func testStripsSurroundingQuotes() {
        let raw = envelope(result: "\"따옴표 제거\"\n'작은따옴표도'")
        XCTAssertEqual(gen.parseCandidates(raw), ["따옴표 제거", "작은따옴표도"])
    }

    func testIgnoresBlankLines() {
        let raw = envelope(result: "한 줄\n\n\n두 줄")
        XCTAssertEqual(gen.parseCandidates(raw), ["한 줄", "두 줄"])
    }

    func testHandlesLeadingShellNoiseBeforeJSON() {
        // 로그인 셸이 stdout에 잡텍스트를 흘려도 { ... } 구간만 파싱.
        let raw = "some profile noise\n" + envelope(result: "가\n나")
        XCTAssertEqual(gen.parseCandidates(raw), ["가", "나"])
    }

    func testGarbageReturnsNil() {
        XCTAssertNil(gen.parseCandidates("not json at all"))
    }

    func testEmptyResultReturnsNil() {
        XCTAssertNil(gen.parseCandidates(envelope(result: "   \n  \n")))
    }
}
