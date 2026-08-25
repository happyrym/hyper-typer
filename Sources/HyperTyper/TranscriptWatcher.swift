import Foundation
import CoreServices

/// ~/.claude/projects 를 FSEvents로 감시해, 파일 변경이 잦아든 뒤(디바운스) 콜백한다.
/// 새 assistant 턴이 append될 때마다 패널이 스스로 후보를 다시 만들게 하는 트리거.
final class TranscriptWatcher {
    private let path: String
    private let onChange: () -> Void
    private let queue = DispatchQueue(label: "com.hypertyper.fsevents")
    private var stream: FSEventStreamRef?
    private var debounce: DispatchWorkItem?

    init(path: String, onChange: @escaping () -> Void) {
        self.path = path
        self.onChange = onChange
    }

    func start() {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagUseCFTypes
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<TranscriptWatcher>.fromOpaque(info).takeUnretainedValue().scheduleDebounced()
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3, flags
        ) else { return }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// 변경 폭주(한 턴에 수십 라인 append)를 흡수 — 마지막 이벤트 후 조용해지면 한 번만 콜백.
    private func scheduleDebounced() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async { self.onChange() }
        }
        debounce = work
        queue.asyncAfter(deadline: .now() + 0.8, execute: work)
    }
}
