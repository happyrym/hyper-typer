import XCTest
@testable import HyperTyper

/// 실제 `claude` CLI를 호출하는 end-to-end 통합 테스트 — 느리고(수십 초) claude 로그인이 필요하다.
/// 기본 `swift test`에서는 건너뛰고, `HT_INTEGRATION=1 swift test --filter IntegrationTests` 로만 실행한다.
final class IntegrationTests: XCTestCase {
    private func requireIntegration() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HT_INTEGRATION"] == "1",
                          "통합 테스트: HT_INTEGRATION=1 일 때만 실행")
    }

    /// early(엔터 직후) — 답변 없이 프롬프트만으로 3개가 나오는지. 실제 후보를 출력한다.
    func testRealEarlyGenerationProducesThree() async throws {
        try requireIntegration()
        let gen = CandidateGenerator()
        let ex = Exchange(userPrompt: "로그인 기능에 rate limit 추가해줘", assistantAnswer: nil)
        let cands = await gen.generate(from: ex, count: 3)
        print("=== EARLY 후보(\(cands.count)) ===")
        cands.forEach { print("  •", $0.text) }
        XCTAssertFalse(cands.contains { $0.text.hasPrefix("⚠️") }, "fallback(실패)이면 안 됨")
        XCTAssertGreaterThanOrEqual(cands.count, 2, "early가 2개 미만이면 프롬프트 개선 필요")
    }

    /// answer(답변 완료 후) — 답변 기반 3개가 나오는지. 실제 후보를 출력한다.
    func testRealAnswerGenerationProducesThree() async throws {
        try requireIntegration()
        let gen = CandidateGenerator()
        let ex = Exchange(
            userPrompt: "로그인 기능에 rate limit 추가해줘",
            assistantAnswer: "rate limit을 추가했습니다. 분당 5회로 제한하고 초과 시 429를 반환하도록 미들웨어를 넣었고, 관련 테스트도 작성했습니다."
        )
        let cands = await gen.generate(from: ex, count: 3)
        print("=== ANSWER 후보(\(cands.count)) ===")
        cands.forEach { print("  •", $0.text) }
        XCTAssertFalse(cands.contains { $0.text.hasPrefix("⚠️") }, "fallback(실패)이면 안 됨")
        XCTAssertGreaterThanOrEqual(cands.count, 2, "answer가 2개 미만이면 프롬프트 개선 필요")
    }
}
