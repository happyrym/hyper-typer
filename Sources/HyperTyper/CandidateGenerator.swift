import Foundation

/// 마지막 교환(직전 사용자 프롬프트 + 답변) → 다음에 보낼 프롬프트 후보 5개. `claude` CLI(print 모드).
/// 키/결제 불필요. 빠르고 깨끗하게: --system-prompt + --strict-mcp-config + --setting-sources ''.
final class CandidateGenerator {
    private func systemPrompt(count: Int) -> String {
        """
        너는 '사용자(개발자)'가 되어, 방금 받은 [어시스턴트 답변]을 읽고 사용자가 어시스턴트에게 '다음에 보낼' 메시지 \(count)개를 쓴다.
        너는 어시스턴트가 아니다 — 답변을 대신 작성하거나 사용자에게 되묻는 질문을 만들지 마라. 오직 '사용자가 어시스턴트에게 칠 다음 한 마디'만.
        형태: 어시스턴트에게 주는 지시/요청/반응 (예: "그대로 진행해줘", "테스트부터 짜줘", "로그인 기록 확인해줘", "왜 이 방식이야?", "3번만 다시해줘").
        금지 예: "어떤 계정이야?", "확인해 봤나?" 처럼 사용자에게 되묻는 형태(이건 어시스턴트 말투다).
        규칙: 답변이 이미 한 일을 다시 시키지 마라. 답변이 사용자에게 뭘 물었으면 그에 답하는 형태를 하나 포함.
        진행/수정/검증/추가지시/대안 중 서로 다르게. 각 40자 이내, 사용자 말투(반말 또는 ~해줘). 기술용어는 영어 그대로.
        출력은 정확히 \(count)줄, 한 줄에 하나. 번호·불릿·따옴표·코드펜스·빈줄·설명 절대 금지.
        """
    }

    /// early(엔터 직후) 전용 — 답변이 아직 없다. 방금 보낸 프롬프트만 보고 '이어서 보낼' 다음 메시지를 예측한다.
    private func earlySystemPrompt(count: Int) -> String {
        """
        너는 '사용자(개발자)'다. 방금 어시스턴트에게 [내 프롬프트]를 보냈고, 아직 답변을 기다리는 중이다.
        답변이 오기 전에 미리, 네가 '이어서 보낼 만한' 다음 메시지 \(count)개를 쓴다.
        너는 어시스턴트가 아니다 — 답변을 대신 쓰거나 사용자에게 되묻는 질문을 만들지 마라. 오직 '내가 어시스턴트에게 칠 다음 한 마디'만.
        서로 다른 방향으로 \(count)개: (1) 방금 요청의 보강·조건 추가, (2) 관련된 다음 단계 지시, (3) 확인·검증 요청 또는 대안 제시.
        예: "그럼 테스트도 같이 붙여줘", "엣지케이스도 처리해줘", "끝나면 커밋까지 해줘", "왜 그 방식이야?", "더 간단한 방법 없어?".
        각 40자 이내, 사용자 말투(반말 또는 ~해줘). 기술용어는 영어 그대로.
        출력은 정확히 \(count)줄, 한 줄에 하나. 번호·불릿·따옴표·코드펜스·빈줄·설명 절대 금지.
        """
    }

    func generate(from exchange: Exchange, count: Int = 5) async -> [Candidate] {
        let prompt = (exchange.userPrompt ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let answer = (exchange.assistantAnswer ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // 답변이 없어도(진행 중·early 스트림) 프롬프트만으로 예측. 둘 다 없을 때만 fallback.
        guard !prompt.isEmpty || !answer.isEmpty else { return fallback(count: count) }
        guard let raw = await runClaudeCLI(userPrompt: exchange.userPrompt, answer: String(answer.prefix(4000)), count: count) else {
            return fallback(count: count, note: "claude CLI 실행 실패/타임아웃")
        }
        guard let cands = parseCandidates(raw), !cands.isEmpty else {
            htLog("GEN-PARSE fail want=\(count) rawLen=\(raw.count) head=\"\(String(raw.prefix(80)))\"")
            return fallback(count: count, note: "후보 파싱 실패")
        }
        htLog("GEN-PARSE want=\(count) got=\(cands.count): \(cands.joined(separator: " | "))")
        return Array(cands.prefix(count)).map { Candidate(text: $0) }
    }

    private func runClaudeCLI(userPrompt: String?, answer: String, count: Int) async -> String? {
        // 답변이 없으면 early(엔터 직후) 모드 — 프롬프트만으로 예측하는 전용 지시를 쓴다.
        let isEarly = answer.isEmpty
        let sys = isEarly ? earlySystemPrompt(count: count) : systemPrompt(count: count)
        let up = userPrompt.map { String($0.prefix(1500)) } ?? "(없음)"
        let context = isEarly
            ? "[방금 내가 보낸 프롬프트]\n\(up)"
            : "[직전 내 프롬프트]\n\(up)\n\n[어시스턴트 답변]\n\(answer)"
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

                // continuation 이중 재개 방지 + 프로세스 hang이어도 caller를 반드시 해제.
                let lock = NSLock()
                var resumed = false
                func finish(_ value: String?) {
                    lock.lock(); defer { lock.unlock() }
                    guard !resumed else { return }
                    resumed = true
                    cont.resume(returning: value)
                }

                do { try process.run() } catch { finish(nil); return }

                // 읽기: 별도 dispatch에서 EOF까지 읽고 핸들을 닫는다(누수 방지).
                DispatchQueue.global().async {
                    let data = out.fileHandleForReading.readDataToEndOfFile()
                    try? out.fileHandleForReading.close()
                    process.waitUntilExit()
                    finish(String(data: data, encoding: .utf8))
                }
                // 워치독: 90초 초과 시 종료하고, hang이어도 caller 해제 보장.
                DispatchQueue.global().asyncAfter(deadline: .now() + 90) {
                    if process.isRunning { process.terminate() }
                    finish(nil)
                }
            }
        }
    }

    /// --output-format json 봉투에서 result를 꺼내 5줄로 파싱. is_error 확인. 번호/불릿/따옴표 제거.
    func parseCandidates(_ raw: String) -> [String]? {
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

    func stripLeadDecoration(_ line: String) -> String {
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

    private func fallback(count: Int = 5, note: String? = nil) -> [Candidate] {
        var items = [
            "좋아, 그대로 진행해줘",
            "테스트부터 작성하고 가자",
            "더 작게 쪼개서 하나씩 보여줘",
            "이 접근을 택한 이유가 뭐야?",
            "방금 바꾼 파일 diff 보여줘",
        ]
        if let note { items.insert("⚠️ \(note)", at: 0) }
        return Array(items.prefix(count)).map { Candidate(text: $0) }
    }
}
