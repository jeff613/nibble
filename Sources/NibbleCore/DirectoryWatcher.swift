import Foundation
import CoreServices

/// Watches a directory tree via FSEvents so quota refreshes track Claude Code
/// activity in near-real-time. Callbacks are debounced and fire on the main queue.
public final class DirectoryWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: () -> Void
    private let debounce: TimeInterval
    private var pending = false

    public init?(url: URL, debounce: TimeInterval = 2, onChange: @escaping () -> Void) {
        self.onChange = onChange
        self.debounce = debounce

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue().fire()
        }

        guard let stream = FSEventStreamCreate(
            nil, callback, &context,
            [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer)
        ) else { return nil }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    private func fire() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce) { [weak self] in
            self?.pending = false
            self?.onChange()
        }
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}
