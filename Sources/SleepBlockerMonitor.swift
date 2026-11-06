import AppKit
import Darwin
import Foundation
import IOKit.pwr_mgt

struct SleepBlocker: Equatable {
    let pid: pid_t
    let name: String
    let bundleIdentifier: String?
    let assertionTypes: Set<String>

    var detail: String {
        let types = assertionTypes.sorted().joined(separator: ", ")
        return "PID \(pid) · \(types)"
    }
}

/// Lists processes that currently hold an assertion preventing idle display
/// sleep. ScreenStay itself is excluded; the menu already shows its own state.
///
/// Uses the public IOPM API. No Accessibility or Screen Recording permission
/// is required.
final class SleepBlockerMonitor {
    private let displayAssertionTypes: Set<String> = [
        kIOPMAssertionTypeNoDisplaySleep as String,
        kIOPMAssertionTypePreventUserIdleDisplaySleep as String
    ]

    /// Returns nil when the power-management assertion database cannot be read.
    func currentBlockers() -> [SleepBlocker]? {
        var rawAssertions: Unmanaged<CFDictionary>?
        let result = IOPMCopyAssertionsByProcess(&rawAssertions)
        guard result == kIOReturnSuccess, let rawAssertions else {
            return nil
        }

        let assertionsByPID = rawAssertions.takeRetainedValue() as NSDictionary
        let ownPID = getpid()
        var merged: [String: SleepBlocker] = [:]

        for (pidKey, assertionsValue) in assertionsByPID {
            guard let pidNumber = pidKey as? NSNumber else { continue }
            let pid = pid_t(pidNumber.intValue)
            guard pid > 0, pid != ownPID else { continue }
            guard let assertions = assertionsValue as? [NSDictionary] else { continue }

            var types = Set<String>()
            for assertion in assertions {
                guard let type = assertion[kIOPMAssertionTypeKey as String] as? String,
                      displayAssertionTypes.contains(type) else {
                    continue
                }
                let level = (assertion[kIOPMAssertionLevelKey as String] as? NSNumber)?.intValue ?? 1
                if level != 0 {
                    types.insert(type)
                }
            }
            guard !types.isEmpty else { continue }

            let application = NSRunningApplication(processIdentifier: pid)
            let bundleIdentifier = application?.bundleIdentifier
            let ownBundleIdentifier = Bundle.main.bundleIdentifier ?? "com.zzerfu.ScreenStay"
            guard bundleIdentifier != ownBundleIdentifier else { continue }

            let name = resolvedName(application: application, pid: pid)
            let mergeKey = bundleIdentifier ?? "name:\(name)"
            let existingTypes = merged[mergeKey]?.assertionTypes ?? []
            let existingPID = merged[mergeKey]?.pid ?? pid

            merged[mergeKey] = SleepBlocker(
                pid: existingPID,
                name: name,
                bundleIdentifier: bundleIdentifier,
                assertionTypes: existingTypes.union(types)
            )
        }

        return merged.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func resolvedName(application: NSRunningApplication?, pid: pid_t) -> String {
        if let name = application?.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }

        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        if length > 0 {
            let path = String(cString: buffer)
            let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            if !name.isEmpty {
                return name
            }
        }

        return "PID \(pid)"
    }
}
