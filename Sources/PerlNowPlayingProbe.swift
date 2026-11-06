import Foundation

/// Uses a tiny bundled dylib loaded by /usr/bin/perl. The system Perl binary
/// is allowed to access MediaRemote on macOS 15.4 and newer, so this gives the
/// authoritative playing/paused state that the app's own MediaRemote calls
/// are denied.
final class PerlNowPlayingProbe {
    private var scriptURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("nowplaying-probe.pl")
    }

    private var libraryURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("libScreenStayNowPlaying.dylib")
    }

    var isAvailable: Bool {
        guard let scriptURL, let libraryURL else { return false }
        return FileManager.default.isExecutableFile(atPath: "/usr/bin/perl")
            && FileManager.default.fileExists(atPath: scriptURL.path)
            && FileManager.default.fileExists(atPath: libraryURL.path)
    }

    /// nil means unavailable or timed out; true/false is authoritative.
    func isPlaying() -> Bool? {
        guard let scriptURL, let libraryURL, isAvailable else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [scriptURL.path, libraryURL.path]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            return nil
        }

        if finished.wait(timeout: .now() + 2.5) == .timedOut {
            process.terminate()
            _ = finished.wait(timeout: .now() + 1.0)
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let value = Int(output) else {
            return nil
        }

        switch value {
        case 1:
            return true
        case 0:
            return false
        default:
            return nil
        }
    }
}
