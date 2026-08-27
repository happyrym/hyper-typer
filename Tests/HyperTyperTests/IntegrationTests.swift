import XCTest
@testable import HyperTyper

/// 실제 `claude` CLI를 호출하는 end-to-end 통합 테스트 — 느리고(수십 초/케이스) claude 로그인이 필요하다.
/// 기본 `swift test`에서는 건너뛰고, `HT_INTEGRATION=1 swift test --filter IntegrationTests` 로만 실행한다.
///
/// 검증 두 겹:
///  1) 구조 — 개수/형식/중복/early≠answer (결정적)
///  2) 시나리오 적합 — claude를 '심사관'으로 호출해 각 후보가 '사용자가 어시스턴트에게 보낼 다음 메시지'로
///     적절한지 true/false 판정(LLM-judge). 다수결로 단언.
final class IntegrationTests: XCTestCase {
    private func requireIntegration() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HT_INTEGRATION"] == "1",
                          "통합 테스트: HT_INTEGRATION=1 일 때만 실행")
    }

    private let userPrompt = "로그인 기능에 rate limit 추가해줘"
    private let answer = "rate limit을 추가했습니다. 분당 5회로 제한하고 초과 시 429를 반환하도록 미들웨어를 넣었고, 관련 테스트도 작성했습니다."

    /// early(엔터 직후, 답변 없음) — 구조 + 시나리오 적합.
    func testEarlyGenerationVerified() async throws {
        try requireIntegration()
        let cands = await CandidateGenerator().generate(
            from: Exchange(userPrompt: userPrompt, assistantAnswer: nil), count: 3)
        print("=== EARLY 후보(\(cands.count)) ==="); cands.forEach { print("  •", $0.text) }

        assertStructure(cands, label: "early")
        let verdicts = await judge(
            context: "사용자가 방금 이 프롬프트를 보냈고 아직 답변을 기다리는 중이다.\n[내 프롬프트] \(userPrompt)",
            candidates: cands.map { $0.text })
        print("  judge:", verdicts)
        XCTAssertGreaterThanOrEqual(verdicts.filter { $0 }.count, 2,
            "early: 시나리오 적합 후보가 2개 미만 (LLM-judge). 후보=\(cands.map { $0.text })")
    }

    /// answer(답변 완료 후) — 구조 + 시나리오 적합.
    func testAnswerGenerationVerified() async throws {
        try requireIntegration()
        let cands = await CandidateGenerator().generate(
            from: Exchange(userPrompt: userPrompt, assistantAnswer: answer), count: 3)
        print("=== ANSWER 후보(\(cands.count)) ==="); cands.forEach { print("  •", $0.text) }

        assertStructure(cands, label: "answer")
        let verdicts = await judge(
            context: "[내 프롬프트] \(userPrompt)\n[어시스턴트 답변] \(answer)",
            candidates: cands.map { $0.text })
        print("  judge:", verdicts)
        XCTAssertGreaterThanOrEqual(verdicts.filter { $0 }.count, 2,
            "answer: 시나리오 적합 후보가 2개 미만 (LLM-judge). 후보=\(cands.map { $0.text })")
    }

    /// early(프롬프트만)와 answer(답변 기반)는 서로 다른 입력이라 결과도 달라야 한다(재활용/중복 방지).
    func testEarlyDiffersFromAnswer() async throws {
        try requireIntegration()
        let gen = CandidateGenerator()
        let early = await gen.generate(from: Exchange(userPrompt: userPrompt, assistantAnswer: nil), count: 3)
        let ans = await gen.generate(from: Exchange(userPrompt: userPrompt, assistantAnswer: answer), count: 3)
        let overlap = Set(early.map { $0.text }).intersection(Set(ans.map { $0.text }))
        print("=== overlap:", overlap)
        XCTAssertLessThanOrEqual(overlap.count, 1, "early와 answer가 거의 동일 → early가 답변 무시 안 함")
    }

    // MARK: - 구조 검증

    private func assertStructure(_ cands: [Candidate], label: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(cands.contains { $0.text.hasPrefix("⚠️") }, "\(label): fallback(생성 실패)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(cands.count, 2, "\(label): 2개 미만", file: file, line: line)
        XCTAssertLessThanOrEqual(cands.count, 3, "\(label): 3개 초과", file: file, line: line)
        let texts = cands.map { $0.text }
        XCTAssertEqual(Set(texts).count, texts.count, "\(label): 중복 후보", file: file, line: line)
        for t in texts {
            XCTAssertFalse(t.trimmingCharacters(in: .whitespaces).isEmpty, "\(label): 빈 후보", file: file, line: line)
            XCTAssertLessThanOrEqual(t.count, 80, "\(label): 너무 긴 후보(>80자): \(t)", file: file, line: line)
            XCTAssertNil(t.range(of: #"^\s*(\d+[.)]|[-*•])\s"#, options: .regularExpression),
                         "\(label): 번호/불릿 접두 남음: \(t)", file: file, line: line)
        }
    }

    // MARK: - LLM-judge (claude를 심사관으로)

    private func judge(context: String, candidates: [String]) async -> [Bool] {
        guard !candidates.isEmpty else { return [] }
        let sys = """
        너는 엄격한 심사관이다. [맥락]을 보고, 각 [후보]가 '사용자(개발자)가 어시스턴트에게 다음에 보낼 메시지'로 적절한지 판정한다.
        적절(true): 어시스턴트에게 주는 지시/요청/반응, 또는 자기 요청의 보강·다음 단계·확인·대안 요청.
        부적절(false): 어시스턴트가 할 법한 답변·설명·요약, 사용자에게 되묻는 어시스턴트 말투, 맥락과 무관, 서로 중복.
        출력은 후보 순서대로 true/false를 담은 JSON 배열 하나만. 예: [true,false,true]. 그 외 설명·문장 절대 금지.
        """
        let numbered = candidates.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        guard let result = await claudeResult(system: sys, prompt: "[맥락]\n\(context)\n\n[후보]\n\(numbered)"),
              let s = result.firstIndex(of: "["), let e = result.lastIndex(of: "]"), s < e,
              let data = String(result[s...e]).data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [Bool] else { return [] }
        return arr
    }

    /// claude -p(json) 호출 후 result 문자열을 돌려준다. 90초 워치독.
    private func claudeResult(system: String, prompt: String) async -> String? {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let dir = "/tmp/hypertyper-genscratch"
                try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/zsh")
                p.arguments = ["-lc",
                    "claude -p \"$J_PROMPT\" --model haiku --output-format json --strict-mcp-config --setting-sources '' --system-prompt \"$J_SYS\""]
                p.currentDirectoryURL = URL(fileURLWithPath: dir)
                var env = ProcessInfo.processInfo.environment
                env["J_PROMPT"] = prompt; env["J_SYS"] = system
                p.environment = env
                let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice
                let lock = NSLock(); var done = false
                func finish(_ v: String?) { lock.lock(); defer { lock.unlock() }; if done { return }; done = true; cont.resume(returning: v) }
                do { try p.run() } catch { finish(nil); return }
                DispatchQueue.global().async {
                    let d = out.fileHandleForReading.readDataToEndOfFile()
                    try? out.fileHandleForReading.close(); p.waitUntilExit()
                    let raw = String(data: d, encoding: .utf8) ?? ""
                    if let s = raw.firstIndex(of: "{"), let e = raw.lastIndex(of: "}"), s < e,
                       let jd = String(raw[s...e]).data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: jd) as? [String: Any],
                       let result = obj["result"] as? String { finish(result) } else { finish(nil) }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 90) {
                    if p.isRunning { p.terminate() }; finish(nil)
                }
            }
        }
    }
}
