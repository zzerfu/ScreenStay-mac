import AppKit
import Foundation

/// Reads the system-wide Now Playing state through MediaRemote.
///
/// MediaRemote is a private framework. Everything here is optional and guarded:
/// if the framework or one of its symbols is unavailable, ScreenStay simply
/// falls back to Core Audio detection. No screen-recording or Accessibility
/// permission is involved.
final class NowPlayingDetector {
    typealias IsPlayingFunction = @convention(c) (
        DispatchQueue,
        @escaping @convention(block) (UInt8) -> Void
    ) -> Void

    typealias PIDFunction = @convention(c) (
        DispatchQueue,
        @escaping @convention(block) (Int32) -> Void
    ) -> Void

    private let queue = DispatchQueue(label: "com.zzerfu.ScreenStay.now-playing", qos: .utility)
    private let jxaReader = JXANowPlayingReader()
    private let perlProbe = PerlNowPlayingProbe()
    private let processAudioDetector = AudioProcessActivityDetector()
    private let frameworkHandle: UnsafeMutableRawPointer?
    private let isPlayingFunction: IsPlayingFunction?
    private let pidFunction: PIDFunction?
    private let requestAPI: Bool

    private var requestInFlight = false
    private var lastRequestAt = Date.distantPast
    private var generation = 0
    private var cachedPlaying = false
    private var cachedAppName: String?
    private var lastCallbackAtStorage: Date?

    /// The last time MediaRemote actually answered. Used to expire stale state.
    var lastCallbackAt: Date? {
        lastCallbackAtStorage
    }

    init() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        frameworkHandle = dlopen(path, RTLD_LAZY | RTLD_LOCAL)

        if let handle = frameworkHandle,
           let isPlayingSymbol = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") {
            isPlayingFunction = unsafeBitCast(isPlayingSymbol, to: IsPlayingFunction.self)
        } else {
            isPlayingFunction = nil
        }

        if let handle = frameworkHandle,
           let pidSymbol = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPID") {
            pidFunction = unsafeBitCast(pidSymbol, to: PIDFunction.self)
        } else {
            pidFunction = nil
        }

        requestAPI = ScreenStayNowPlayingRequestAvailable()
    }

    var isAvailable: Bool {
        perlProbe.isAvailable || jxaReader.isAvailable || requestAPI || isPlayingFunction != nil
    }

    /// Asks MediaRemote for the current state. Completion is always called on
    /// the main queue. If a previous request is still pending, the cached
    /// result is returned to avoid piling up IPC calls.
    func refresh(completion: @escaping (Bool, String?) -> Void) {
        guard perlProbe.isAvailable || jxaReader.isAvailable || requestAPI || isPlayingFunction != nil else {
            completion(false, nil)
            return
        }

        let now = Date()
        if requestInFlight, now.timeIntervalSince(lastRequestAt) < 4.0 {
            completion(cachedPlaying, cachedAppName)
            return
        }

        requestInFlight = true
        lastRequestAt = now
        generation += 1
        let requestGeneration = generation

        if perlProbe.isAvailable {
            queue.async { [weak self] in
                guard let self, requestGeneration == self.generation else { return }

                let perlPlaying = self.perlProbe.isPlaying()
                if perlPlaying == false {
                    DispatchQueue.main.async {
                        self.finish(
                            generation: requestGeneration,
                            playing: false,
                            appName: nil,
                            completion: completion
                        )
                    }
                    return
                }

                let snapshot = self.jxaReader.read()
                var playing = perlPlaying ?? (snapshot?.isPlaying ?? false)

                // If the Perl probe timed out, fall back to the process audio
                // confirmation before trusting a stale PlaybackRate.
                if playing, perlPlaying == nil, let snapshot {
                    let metadataPlaying = snapshot.metadataSaysPlaying ?? false
                    let processOutput = self.processAudioDetector.isOutputRunning(
                        pid: snapshot.pid,
                        bundleIdentifier: snapshot.bundleIdentifier
                    )
                    playing = metadataPlaying || (processOutput ?? true)
                }

                DispatchQueue.main.async {
                    self.finish(
                        generation: requestGeneration,
                        playing: playing,
                        appName: playing ? snapshot?.appName : nil,
                        completion: completion
                    )
                }
            }
            return
        }

        if jxaReader.isAvailable {
            queue.async { [weak self] in
                guard let self, requestGeneration == self.generation else { return }
                let snapshot = self.jxaReader.read()
                var playing = snapshot?.isPlaying ?? false

                // PlaybackRate can remain 1 after a pause, especially when a
                // player leaves its Now Playing metadata untouched. Require
                // either per-process audio output or the player's own
                // isCurrentlyPlaying flag before keeping the display awake.
                if playing, let snapshot {
                    let metadataPlaying = snapshot.metadataSaysPlaying ?? false
                    let processOutput = self.processAudioDetector.isOutputRunning(
                        pid: snapshot.pid,
                        bundleIdentifier: snapshot.bundleIdentifier
                    )
                    playing = metadataPlaying || (processOutput ?? true)
                }

                DispatchQueue.main.async {
                    self.finish(
                        generation: requestGeneration,
                        playing: playing,
                        appName: playing ? snapshot?.appName : nil,
                        completion: completion
                    )
                }
            }
            return
        }

        if requestAPI {
            queue.async { [weak self] in
                guard let self, requestGeneration == self.generation else { return }
                let playing = ScreenStayNowPlayingIsPlaying()
                let appName = playing ? ScreenStayNowPlayingApplicationName() : nil
                DispatchQueue.main.async {
                    self.finish(
                        generation: requestGeneration,
                        playing: playing,
                        appName: appName,
                        completion: completion
                    )
                }
            }
            return
        }

        guard let isPlayingFunction else {
            completion(false, nil)
            return
        }

        isPlayingFunction(queue) { [weak self] rawValue in
            guard let self, requestGeneration == self.generation else { return }
            let playing = rawValue != 0

            guard playing, let pidFunction = self.pidFunction else {
                DispatchQueue.main.async {
                    self.finish(
                        generation: requestGeneration,
                        playing: playing,
                        appName: nil,
                        completion: completion
                    )
                }
                return
            }

            pidFunction(self.queue) { [weak self] pid in
                guard let self, requestGeneration == self.generation else { return }
                DispatchQueue.main.async {
                    let appName: String?
                    if pid > 0,
                       let application = NSRunningApplication(processIdentifier: pid_t(pid)) {
                        appName = application.localizedName
                    } else {
                        appName = nil
                    }
                    self.finish(
                        generation: requestGeneration,
                        playing: playing,
                        appName: appName,
                        completion: completion
                    )
                }
            }
        }
    }

    private func finish(
        generation requestGeneration: Int,
        playing: Bool,
        appName: String?,
        completion: (Bool, String?) -> Void
    ) {
        guard requestGeneration == generation else { return }
        requestInFlight = false
        lastCallbackAtStorage = Date()
        cachedPlaying = playing
        cachedAppName = playing ? appName : nil
        completion(playing, cachedAppName)
    }
}
