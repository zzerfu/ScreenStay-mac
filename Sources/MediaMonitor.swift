import AppKit
import Foundation

struct MediaState: Equatable {
    var isPlaying = false
    var source: String?
    var audioActive = false
    var nowPlayingActive = false
}

/// Combines the two playback signals and adds debounce, so notification
/// sounds or a single click in a video do not keep the display awake.
final class MediaMonitor {
    private let audioDetector = AudioActivityDetector()
    private let nowPlayingDetector = NowPlayingDetector()

    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var audioRaw = false
    private var nowPlayingRaw = false
    private var nowPlayingAppName: String?
    private var activeSince: Date?
    private var lastRawActiveAt: Date?
    private var lastNowPlayingUpdate: Date?
    private var lastEmittedState = MediaState()

    private(set) var state = MediaState()
    var onUpdate: ((MediaState) -> Void)?

    var isNowPlayingAvailable: Bool {
        nowPlayingDetector.isAvailable
    }

    /// When true, only the system Now Playing list may trigger ScreenStay.
    /// Core Audio is not sampled at all, so notification sounds and other
    /// short-lived output cannot keep the display awake.
    var nowPlayingOnly = true {
        didSet {
            guard oldValue != nowPlayingOnly else { return }
            audioRaw = false
            activeSince = nil
            lastRawActiveAt = nil
            state.isPlaying = false
            state.source = nil

            if timer != nil {
                tick()
            } else {
                recompute()
            }
        }
    }

    func start() {
        guard timer == nil else { return }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.tick()
        }

        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        audioRaw = false
        nowPlayingRaw = false
        nowPlayingAppName = nil
        activeSince = nil
        lastRawActiveAt = nil
        lastNowPlayingUpdate = nil
        state = MediaState()
        lastEmittedState = MediaState()
    }

    private func tick() {
        let now = Date()
        if nowPlayingOnly {
            // Deliberately do not sample Core Audio in strict mode. Some apps
            // keep an output stream running with silence, and notification
            // sounds would otherwise look like media playback.
            audioRaw = false
        } else {
            audioRaw = audioDetector.isOutputActive()
        }

        // If mediaremoted stops answering, do not trust the old answer forever.
        if let lastNowPlayingUpdate, now.timeIntervalSince(lastNowPlayingUpdate) > 8 {
            nowPlayingRaw = false
            nowPlayingAppName = nil
        }

        nowPlayingDetector.refresh { [weak self] playing, appName in
            guard let self else { return }
            // Ignore a cached answer if mediaremoted has not answered for a
            // while; otherwise a stale "playing" state could stick forever.
            if let callbackAt = self.nowPlayingDetector.lastCallbackAt,
               Date().timeIntervalSince(callbackAt) <= 8 {
                self.lastNowPlayingUpdate = callbackAt
                self.nowPlayingRaw = playing
                self.nowPlayingAppName = playing ? appName : nil
            } else {
                self.lastNowPlayingUpdate = nil
                self.nowPlayingRaw = false
                self.nowPlayingAppName = nil
            }
            self.recompute()
        }

        recompute()
    }

    private func recompute() {
        let now = Date()
        let rawActive = nowPlayingOnly ? nowPlayingRaw : (audioRaw || nowPlayingRaw)

        if rawActive {
            if activeSince == nil {
                activeSince = now
            }
            lastRawActiveAt = now
        } else {
            activeSince = nil
        }

        if rawActive {
            if !state.isPlaying {
                let stableFor = activeSince.map { now.timeIntervalSince($0) } ?? 0
                // Now Playing is a strong signal and can be trusted immediately.
                // Raw audio alone must last a few seconds to skip UI sounds.
                if nowPlayingRaw || stableFor >= 2.5 {
                    state.isPlaying = true
                }
            }
        } else if state.isPlaying, let lastRawActiveAt {
            let releaseDelay = nowPlayingOnly ? 1.0 : 5.0
            if now.timeIntervalSince(lastRawActiveAt) >= releaseDelay {
                state.isPlaying = false
            }
        }

        state.audioActive = audioRaw
        state.nowPlayingActive = nowPlayingRaw

        if state.isPlaying {
            if nowPlayingRaw, let nowPlayingAppName, !nowPlayingAppName.isEmpty {
                state.source = nowPlayingAppName
            } else if state.source == nil {
                state.source = "媒体"
            }
        } else {
            state.source = nil
        }

        guard state != lastEmittedState else { return }
        lastEmittedState = state
        onUpdate?(state)
    }
}
