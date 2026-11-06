import Foundation
import IOKit.pwr_mgt

/// Owns the two IOPM assertions that keep the display and system awake.
final class PowerController {
    private var displayAssertionID: IOPMAssertionID = 0
    private var systemAssertionID: IOPMAssertionID = 0

    private(set) var isHeld = false
    private(set) var lastError: String?

    func apply(shouldHold: Bool) {
        if shouldHold {
            acquireIfNeeded()
        } else {
            release()
        }
    }

    func acquireIfNeeded() {
        guard !isHeld else { return }

        let reason = "ScreenStay: media is playing" as CFString
        let level = IOPMAssertionLevel(kIOPMAssertionLevelOn)
        var displayID: IOPMAssertionID = 0
        var systemID: IOPMAssertionID = 0

        let displayResult = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            level,
            reason,
            &displayID
        )
        let systemResult = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            level,
            reason,
            &systemID
        )

        if displayResult == kIOReturnSuccess {
            displayAssertionID = displayID
        }
        if systemResult == kIOReturnSuccess {
            systemAssertionID = systemID
        }

        isHeld = displayAssertionID != 0 || systemAssertionID != 0
        if !isHeld {
            lastError = String(
                format: "电源断言创建失败（display 0x%08X, system 0x%08X）",
                displayResult,
                systemResult
            )
        } else {
            lastError = nil
        }
    }

    func release() {
        if displayAssertionID != 0 {
            IOPMAssertionRelease(displayAssertionID)
            displayAssertionID = 0
        }
        if systemAssertionID != 0 {
            IOPMAssertionRelease(systemAssertionID)
            systemAssertionID = 0
        }
        isHeld = false
        lastError = nil
    }

    deinit {
        release()
    }
}
