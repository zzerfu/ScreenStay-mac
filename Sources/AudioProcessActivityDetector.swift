import CoreAudio
import Foundation

/// Checks whether the process that owns the Now Playing session is currently
/// running an output stream.
///
/// A paused player often leaves `PlaybackRate = 1` and the elapsed timestamp
/// untouched in its Now Playing metadata. The per-process Core Audio property
/// is a much better pause signal: it drops to 0 shortly after playback pauses.
final class AudioProcessActivityDetector {
    private let systemObject = AudioObjectID(kAudioObjectSystemObject)

    /// Returns nil when process audio objects are unavailable (older macOS or
    /// a transient Core Audio error). Callers should then fall back to the
    /// player's own Now Playing metadata.
    func isOutputRunning(pid: Int32?, bundleIdentifier: String?) -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr,
              size >= UInt32(MemoryLayout<AudioObjectID>.size) else {
            return nil
        }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var objects = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &objects) == noErr else {
            return nil
        }

        let wantedPID = (pid ?? 0) > 0 ? pid : nil
        let wantedBundle = bundleIdentifier?.isEmpty == false ? bundleIdentifier : nil
        for object in objects {
            let processPID = pidOf(object)
            let processBundle = bundleIDOf(object)

            let pidMatches = wantedPID.map { processPID == $0 } ?? false
            let bundleMatches: Bool
            if let wantedBundle, let processBundle {
                bundleMatches = processBundle == wantedBundle
                    || processBundle.hasPrefix(wantedBundle + ".")
            } else {
                bundleMatches = false
            }

            guard pidMatches || bundleMatches else { continue }
            if isRunningOutput(object) {
                return true
            }
        }

        // No active output for the Now Playing app. The caller can still use
        // the player's own metadata flag for muted video playback.
        return false
    }

    private func pidOf(_ object: AudioObjectID) -> Int32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else {
            return 0
        }
        return Int32(value)
    }

    private func bundleIDOf(_ object: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString? = nil
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }
        guard status == noErr else { return nil }
        return value as String?
    }

    private func isRunningOutput(_ object: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else {
            return false
        }
        return value != 0
    }
}
