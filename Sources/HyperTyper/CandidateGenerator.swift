import Foundation

/// 마지막 교환(직전 사용자 프롬프트 + 답변) → 다음에 보낼 프롬프트 후보 5개. `claude` CLI(print 모드).
/// 키/결제 불필요. 빠르고 깨끗하게: --system-prompt + --strict-mcp-config + --setting-sources ''.
final class CandidateGenerator {
    private let systemPrompt = """
    너는 개발자(사용자)가 AI 어시스턴트와 나누는 대화를 돕는다. [직전 내 프롬프트]와 [어시스턴트 답변]을 보고,
    내가 '다음에 보낼' 짧은 한국어 메시지 5개를 제안하라.
    핵심 규칙:
    - 답변이 이미 완료한 작업을 다시 시키지 마라. 완료된 단계 반복 금지.
    - 대화의 실제 '다음 한 수'만: 진행 승인 / 방향 수정 / 결과 검증 / 되묻기 / 대안 제시 중 서로 다르게.
    - 답변이 사용자에게 뭔가 물었으면, 그에 답하는 형태를 반드시 하나 포함.
    - 개발자가 툭 던지듯 짧게. 각 40자 이내, 명령/반응형. 기술용어는 영어 그대로.
    출력은 정확히 5줄, 한 줄에 하나. 번호·불릿·따옴표·코드펜스·빈줄·설명 절대 금지.
    """

    func generate(from exchange: Exchange) async -> [Candidate] {
        let prompt = (exchange.userPrompt ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let answer = (exchange.assistantAnswer ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // 답변이 없어도(진행 중) 프롬프트만으로 예측. 둘 다 없을 때만 fallback.
        guard !prompt.isEmpty || !answer.isEmpty else { return fallback() }
        guard let raw = await runClaudeCLI(userPrompt: exchange.userPrompt, answer: String(answer.prefix(4000))) else {
            return fallback(note: "claude CLI 실행 실패/타임아웃")
        }
        guard let cands = parseCandidates(raw), !cands.isEmpty else {
            return fallback(note: "후보 파싱 실패")
        }
        return Array(cands.prefix(5)).map { Candidate(text: $0) }
    }

    private func runClaudeCLI(userPrompt: String?, answer: String) async -> String? {
        let sys = systemPrompt
        let up = userPrompt.map { String($0.prefix(1500)) } ?? "(없음)"
        let ans = answer.isEmpty ? "(아직 없음 — 방금 이 프롬프트를 보냈고 진행 중)" : answer
        let context = "[직전 내 프롬프트]\n\(up)\n\n[어시스턴트 답변]\n\(ans)"
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                // 격리된 scratch cwd — 생성용 claude -p의 transcript가 여기 쌓이며,
                // 리더가 이 경로를 제외해 '자기 생성이 자기를 트리거하는' 피드백 루프를 끊는다.
                let genDir = "/tmp/hypertyper-genscratch"
                try? FileManager.default.createDirectory(atPath: genDir, withIntermediateDirectories: true)

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-lc",
                    "claude -p \"$HT_PROMPT\" --model haiku --output-format json --strict-mcp-config --setting-sources '' --system-prompt \"$HT_SYS\""]
                process.currentDirectoryURL = URL(fileURLWithPath: genDir)
                var env = ProcessInfo.processInfo.environment
                env["HT_PROMPT"] = context
                env["HT_SYS"] = sys
                process.environment = env

                let out = Pipe()
                process.standardOutput = out
                process.standardError = FileHandle.nullDevice

                do { try process.run() } catch { cont.resume(returning: nil); return }

                let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + 90, execute: watchdog)

                let data = out.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                watchdog.cancel()

                cont.resume(returning: String(data: data, encoding: .utf8))
            }
        }
    }

    /// --output-format json 봉투에서 result를 꺼내 5줄로 파싱. is_error 확인. 번호/불릿/따옴표 제거.
    private func parseCandidates(_ raw: String) -> [String]? {
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"), start < end,
              let data = String(raw[start...end]).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let isError = obj["is_error"] as? Bool, isError { return nil }
        guard let result = obj["result"] as? String else { return nil }

        let lines = result.split(separator: "\n")
            .map { stripLeadDecoration(String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
        return lines.isEmpty ? nil : lines
    }

    private func stripLeadDecoration(_ line: String) -> String {
        var s = line
        if let r = s.range(of: #"^\s*(\d+[.)]|[-*•])\s+"#, options: .regularExpression) {
            s.removeSubrange(r)
        }
        s = s.trimmingCharacters(in: .whitespaces)
        if s.count >= 2, let f = s.first, let l = s.last,
           (f == "\"" && l == "\"") || (f == "'" && l == "'") {
            s = String(s.dropFirst().dropLast())
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    private func fallback(note: String? = nil) -> [Candidate] {
        var items = [
            "좋아, 그대로 진행해줘",
            "테스트부터 작성하고 가자",
            "더 작게 쪼개서 하나씩 보여줘",
            "이 접근을 택한 이유가 뭐야?",
            "방금 바꾼 파일 diff 보여줘",
        ]
        if let note { items.insert("⚠️ \(note)", at: 0) }
        return Array(items.prefix(5)).map { Candidate(text: $0) }
    }
}
