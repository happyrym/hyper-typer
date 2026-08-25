import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel!
    private var tracker: OrcaWindowTracker!
    private var watcher: TranscriptWatcher!
    private var statusBar: StatusBarController!
    private let store = CandidateStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let view = PanelView(store: store)
        panel = FloatingPanel(view: view)
        panel.orderFrontRegardless()

        // 메뉴바 아이콘(실행 표시 + 종료/새로고침).
        statusBar = StatusBarController(onRefresh: { [weak self] in self?.store.refreshFromTranscript() })

        // Orca 창을 추적해 패널을 그 위에 앵커링.
        tracker = OrcaWindowTracker { [weak self] frame, windowID in
            self?.panel.follow(orcaFrame: frame, windowID: windowID)
        }
        tracker.start()

        // transcript(~/.claude/projects) 변경을 감시 → 트리거. end_turn 필터 덕에 턴이 실제로
        // 끝났을 때만 답변이 바뀌어 재생성된다(중간 툴 호출 텍스트는 무시). 세션 정밀도는
        // resolveExchange가 last-turn.json(등록 시)을 우선 참조해 얹는다. hook 미등록이어도 동작.
        let htDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hyper-typer", isDirectory: true)
        try? FileManager.default.createDirectory(at: htDir, withIntermediateDirectories: true)
        let projects = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true).path
        watcher = TranscriptWatcher(path: projects) { [weak self] in
            MainActor.assumeIsolated { self?.store.refreshIfChanged() }
        }
        watcher.start()

        // 첫 로드: 직전 assistant 턴으로 후보 생성.
        store.refreshFromTranscript()
    }
}
