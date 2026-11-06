import AppKit
import Foundation

private let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.contains("--version") {
    print("ScreenStay 1.2.3")
    exit(0)
}

if arguments.contains("--login-status") {
    let manager = LoginItemManager()
    print(manager.debugDescription)
    exit(0)
}

if arguments.contains("--enable-login") {
    let manager = LoginItemManager()
    do {
        let needsApproval = try manager.setEnabled(true)
        print("status=\(manager.statusName) needsApproval=\(needsApproval)")
        exit(needsApproval ? 2 : 0)
    } catch {
        fputs("error=\(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

if arguments.contains("--disable-login") {
    let manager = LoginItemManager()
    do {
        _ = try manager.setEnabled(false)
        print("status=\(manager.statusName)")
        exit(0)
    } catch {
        fputs("error=\(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

if arguments.contains("--nowplaying") {
    let perlProbe = PerlNowPlayingProbe()
    print("perlAvailable=\(perlProbe.isAvailable)")
    print("perlIsPlaying=\(perlProbe.isPlaying().map(String.init) ?? "unknown")")

    let reader = JXANowPlayingReader()
    if let snapshot = reader.read() {
        print("source=jxa")
        print("isPlaying=\(snapshot.isPlaying)")
        print("playbackRate=\(snapshot.playbackRate)")
        print("app=\(snapshot.appName ?? "-")")
        print("title=\(snapshot.title ?? "-")")
        print("pid=\(snapshot.pid ?? -1)")
        print("bundle=\(snapshot.bundleIdentifier ?? "-")")
        print("metadataPlaying=\(snapshot.metadataSaysPlaying.map(String.init) ?? "unknown")")
        let processOutput = AudioProcessActivityDetector().isOutputRunning(
            pid: snapshot.pid,
            bundleIdentifier: snapshot.bundleIdentifier
        )
        print("processAudio=\(processOutput.map(String.init) ?? "unknown")")
    } else {
        print("source=jxa-unavailable")
    }

    let available = ScreenStayNowPlayingRequestAvailable()
    print("requestAPI=\(available)")
    print("isPlaying=\(ScreenStayNowPlayingIsPlaying())")
    print("playbackState=\(ScreenStayNowPlayingPlaybackState())")
    print("app=\(ScreenStayNowPlayingApplicationName() ?? "-")")
    print("bundle=\(ScreenStayNowPlayingBundleIdentifier() ?? "-")")
    print("requestState=\(ScreenStayNowPlayingRequestPlaybackState())")
    print("requestIsPlaying=\(ScreenStayNowPlayingRequestIsPlaying())")
    print("requestRate=\(ScreenStayNowPlayingRequestPlaybackRate())")
    exit(0)
}

if arguments.contains("--blockers") {
    guard let blockers = SleepBlockerMonitor().currentBlockers() else {
        print("unavailable")
        exit(1)
    }
    if blockers.isEmpty {
        print("none")
    } else {
        for blocker in blockers {
            let types = blocker.assertionTypes.sorted().joined(separator: ",")
            print("\(blocker.name)\tpid=\(blocker.pid)\ttypes=\(types)")
        }
    }
    exit(0)
}

if arguments.contains("--diagnose") {
    var seconds: TimeInterval = 8
    if let index = arguments.firstIndex(of: "--diagnose"),
       arguments.indices.contains(index + 1),
       let value = TimeInterval(arguments[index + 1]) {
        seconds = max(1, min(value, 120))
    }
    Diagnostics.run(seconds: seconds)
    exit(0)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
