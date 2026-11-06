import Foundation

enum Diagnostics {
    static func run(seconds: TimeInterval) {
        let monitor = MediaMonitor()
        let power = PowerController()
        let startedAt = Date()
        let deadline = startedAt.addingTimeInterval(seconds)
        let nowPlayingOnly = UserDefaults.standard.object(
            forKey: "nowPlayingOnly"
        ) as? Bool ?? true
        monitor.nowPlayingOnly = nowPlayingOnly

        print("ScreenStay diagnostics")
        print("  nowPlaying API: \(monitor.isNowPlayingAvailable ? "available" : "unavailable")")
        print("  trigger: \(nowPlayingOnly ? "Now Playing only (strict)" : "audio + Now Playing")")
        print("  duration: \(Int(seconds))s")
        print("  time       audio  nowPlaying  playing  assertion  source")
        fflush(stdout)

        func printStatus() {
            let state = monitor.state
            let elapsed = String(format: "+%.1fs", Date().timeIntervalSince(startedAt))
            print(
                "[\(elapsed)] audio=\(state.audioActive ? "yes" : "no") " +
                "nowPlaying=\(state.nowPlayingActive ? "yes" : "no") " +
                "playing=\(state.isPlaying ? "yes" : "no") " +
                "assertion=\(power.isHeld ? "held" : "none") " +
                "source=\(state.source ?? "-")"
            )
            fflush(stdout)
        }

        monitor.onUpdate = { state in
            power.apply(shouldHold: state.isPlaying)
            printStatus()
        }

        let timer = Timer(timeInterval: 2.0, repeats: true) { _ in
            printStatus()
        }
        RunLoop.main.add(timer, forMode: .common)

        monitor.start()
        printStatus()

        while Date() < deadline {
            RunLoop.main.run(
                mode: .default,
                before: Date().addingTimeInterval(0.2)
            )
        }

        timer.invalidate()
        monitor.stop()
        power.release()
        printStatus()
        print("done")
        fflush(stdout)
    }
}

