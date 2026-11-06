import Foundation

struct NowPlayingSnapshot {
    let isPlaying: Bool
    let appName: String?
    let title: String?
    let playbackRate: Double
    let pid: Int32?
    let bundleIdentifier: String?
    let metadataSaysPlaying: Bool?
}

/// Reads Now Playing through a small JXA helper executed by
/// `/usr/bin/osascript`.
///
/// On macOS 15.4 and newer, MediaRemote's C API and the `MRNowPlayingRequest`
/// class properties return Paused for third-party apps. Platform binaries such
/// as osascript are still allowed to read the now-playing item, so this is the
/// reliable path for getting the real playback rate.
final class JXANowPlayingReader {
    private let script = """
    function run() {
        const bundle = $.NSBundle.bundleWithPath(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/"
        );
        bundle.load;
        const requestClass = $.NSClassFromString("MRNowPlayingRequest");
        if (!requestClass) {
            return JSON.stringify({ available: false });
        }

        let appName = "";
        let bundleIdentifier = "";
        let pid = 0;
        const playerPath = requestClass.localNowPlayingPlayerPath;
        if (playerPath && playerPath.client) {
            const displayName = playerPath.client.displayName;
            if (displayName) {
                appName = String(displayName.js);
            }
            const bundle = playerPath.client.bundleIdentifier;
            if (bundle) {
                bundleIdentifier = String(bundle.js);
            }
            const processIdentifier = playerPath.client.processIdentifier;
            if (processIdentifier !== undefined && processIdentifier !== null) {
                const parsedPID = Number(
                    processIdentifier.js !== undefined
                        ? processIdentifier.js
                        : processIdentifier
                );
                if (!isNaN(parsedPID)) {
                    pid = parsedPID;
                }
            }
        }

        let title = "";
        let rate = 0;
        let metadataPlaying = null;
        const item = requestClass.localNowPlayingItem;
        if (item) {
            const metadata = item.metadata;
            if (metadata) {
                const currentlyPlaying = metadata.isCurrentlyPlaying;
                if (typeof currentlyPlaying === "boolean") {
                    metadataPlaying = currentlyPlaying;
                }
            }
            const info = item.nowPlayingInfo;
            if (info) {
                const titleValue = info.valueForKey(
                    "kMRMediaRemoteNowPlayingInfoTitle"
                );
                const rateValue = info.valueForKey(
                    "kMRMediaRemoteNowPlayingInfoPlaybackRate"
                );
                if (titleValue) {
                    title = String(titleValue.js);
                }
                if (rateValue) {
                    const parsed = Number(rateValue.js);
                    if (!isNaN(parsed)) {
                        rate = parsed;
                    }
                }
            }
        }

        return JSON.stringify({
            available: true,
            app: appName,
            bundle: bundleIdentifier,
            pid: pid,
            title: title,
            rate: rate,
            metadataPlaying: metadataPlaying
        });
    }
    """

    var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: "/usr/bin/osascript")
    }

    /// Synchronous; call from a background queue.
    func read() -> NowPlayingSnapshot? {
        guard isAvailable else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", script]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            return nil
        }

        if finished.wait(timeout: .now() + 3.0) == .timedOut {
            process.terminate()
            _ = finished.wait(timeout: .now() + 1.0)
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let trimmed = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty,
              let jsonData = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: jsonData),
              let dictionary = object as? [String: Any],
              dictionary["available"] as? Bool == true else {
            return nil
        }

        let appName = (dictionary["app"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (dictionary["title"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rate = (dictionary["rate"] as? NSNumber)?.doubleValue ?? 0.0
        let pid = (dictionary["pid"] as? NSNumber)?.int32Value
        let bundleIdentifier = (dictionary["bundle"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let metadataSaysPlaying = dictionary["metadataPlaying"] as? Bool

        return NowPlayingSnapshot(
            isPlaying: rate > 0.001,
            appName: appName?.isEmpty == false ? appName : nil,
            title: title?.isEmpty == false ? title : nil,
            playbackRate: rate,
            pid: pid,
            bundleIdentifier: bundleIdentifier?.isEmpty == false ? bundleIdentifier : nil,
            metadataSaysPlaying: metadataSaysPlaying
        )
    }
}
