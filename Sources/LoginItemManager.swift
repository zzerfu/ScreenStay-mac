import AppKit
import Foundation
import ServiceManagement

final class LoginItemManager {
    var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    var isOn: Bool {
        status == .enabled || status == .requiresApproval
    }

    var statusName: String {
        switch status {
        case .enabled:
            return "enabled"
        case .requiresApproval:
            return "requiresApproval"
        case .notRegistered:
            return "notRegistered"
        case .notFound:
            return "notFound"
        @unknown default:
            return "unknown(\(status.rawValue))"
        }
    }

    var debugDescription: String {
        "status=\(statusName) raw=\(status.rawValue) bundle=\(Bundle.main.bundlePath)"
    }

    /// Returns true when macOS accepted the registration but still needs the
    /// user to approve the login item in System Settings.
    @discardableResult
    func setEnabled(_ enabled: Bool) throws -> Bool {
        let service = SMAppService.mainApp

        if enabled {
            switch service.status {
            case .enabled:
                return false
            case .requiresApproval:
                return true
            default:
                try service.register()
            }
        } else {
            switch service.status {
            case .notRegistered, .notFound:
                return false
            default:
                try service.unregister()
            }
        }

        return service.status == .requiresApproval
    }

    func openLoginItemsSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
