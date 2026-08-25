import Foundation

/// 대화의 한 교환: 직전 사용자 프롬프트 + 직전 assistant 답변.
struct Exchange {
    let userPrompt: String?
    let assistantAnswer: String?
}

/// Claude Code 세션 transcript(JSONL)에서 마지막 교환을 읽는다.
/// assistant는 한 응답이 여러 줄로 쪼개져 같은 message.id 공유 → id 그룹핑, text 블록만.
/// user는 실제 프롬프트일 때 message.content가 String(툴 결과는 배열이라 제외).
final class TranscriptReader {
    private let projectsDir: URL

    init() {
        projectsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    /// 특정 transcript 파일(Stop hook이 알려준 경로)의 마지막 교환.
    func exchange(atPath path: String) -> Exchange {
        parseExchange(from: URL(fileURLWithPath: path))
    }

    /// 폴백: 가장 최근 세션의 마지막 교환.
    func latestExchange() -> Exchange {
        guard let url = latestTranscriptURL() else { return Exchange(userPrompt: nil, assistantAnswer: nil) }
        return parseExchange(from: url)
    }

    /// 터미널별 스코핑: '가장 최근 새 user 메시지'가 있는 세션의 마지막 교환.
    /// 백그라운드 에이전트(assistant만 append)는 user 발화가 없어 이 선택을 못 바꾼다 → 크로스 트리거 차단.
    func mostRecentUserExchange() -> Exchange {
        guard let url = mostRecentUserSessionURL() else { return Exchange(userPrompt: nil, assistantAnswer: nil) }
        return parseExchange(from: url)
    }

    private func mostRecentUserSessionURL() -> URL? {
        let cutoff = Date().addingTimeInterval(-900) // 최근 15분 내 활동 세션만
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let en = FileManager.default.enumerator(at: projectsDir, includingPropertiesForKeys: keys) else { return nil }

        var recent: [URL] = []
        for case let url as URL in en where url.pathExtension == "jsonl" {
            if url.path.contains("/subagents/") { continue }
            if url.path.contains("hypertyper-genscratch") || url.path.contains("-private-tmp") { continue }
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if mtime > cutoff { recent.append(url) }
        }

        var best: (url: URL, ts: String)?
        for url in recent {
            guard let ts = lastUserTimestamp(from: url) else { continue }
            if best == nil || ts > best!.ts { best = (url, ts) }
        }
        return best?.url
    }

    /// 해당 transcript에서 마지막 '실제 user 프롬프트'(content가 String)의 timestamp(ISO8601).
    private func lastUserTimestamp(from url: URL) -> String? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var last: String?
        for line in content.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (obj["type"] as? String) == "user",
                  let message = obj["message"] as? [String: Any],
                  message["content"] is String,
                  let ts = obj["timestamp"] as? String else { continue }
            last = ts
        }
        return last
    }

    /// 가장 최근 수정된 .jsonl (subagents 제외).
    func latestTranscriptURL() -> URL? {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: projectsDir, includingPropertiesForKeys: keys) else { return nil }
        var newest: (url: URL, date: Date)?
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            if url.path.contains("/subagents/") { continue }
            // 우리 생성용 claude -p가 남긴 transcript는 제외(피드백 루프 차단).
            if url.path.contains("hypertyper-genscratch") || url.path.contains("-private-tmp") { continue }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if newest == nil || date > newest!.date { newest = (url, date) }
        }
        return newest?.url
    }

    private func parseExchange(from url: URL) -> Exchange {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return Exchange(userPrompt: nil, assistantAnswer: nil)
        }
        var order: [String] = []
        var textsByID: [String: [String]] = [:]
        var stopByID: [String: String] = [:]   // message.id → stop_reason
        var lastUser: String?

        for line in content.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = obj["type"] as? String,
                  let message = obj["message"] as? [String: Any] else { continue }

            if type == "user" {
                if let s = message["content"] as? String, !s.isEmpty { lastUser = s }
            } else if type == "assistant", let blocks = message["content"] as? [[String: Any]] {
                let id = (message["id"] as? String) ?? UUID().uuidString
                if let sr = message["stop_reason"] as? String { stopByID[id] = sr }
                for block in blocks where (block["type"] as? String) == "text" {
                    guard let text = block["text"] as? String else { continue }
                    if textsByID[id] == nil { order.append(id) }
                    textsByID[id, default: []].append(text)
                }
            }
        }
        // 툴 호출로 이어지는 중간 텍스트("Now build and…" 등)는 제외.
        // stop_reason == end_turn 인 마지막 그룹(= 실제 최종 답변) 우선, 없으면 마지막 텍스트 그룹.
        let chosenID = order.last(where: { stopByID[$0] == "end_turn" }) ?? order.last
        let answer = chosenID.flatMap { textsByID[$0] }?.joined(separator: "\n")
        return Exchange(userPrompt: lastUser, assistantAnswer: answer)
    }
}
