import CoreGraphics
import Foundation

/// `CGPreflightScreenCaptureAccess` returns `false` for both denied and
/// not-yet-determined, so the OS state alone can't distinguish them. We
/// remember whether the user has been prompted in UserDefaults; once a request
/// has been made and preflight still returns false, the user has explicitly
/// denied access and should be sent to System Settings.
final class SystemPermissionService: PermissionService {
    private static let hasRequestedKey = "permissions.screenRecording.hasRequested"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func refreshPermissions() async -> PermissionStatus {
        if CGPreflightScreenCaptureAccess() {
            return .granted
        }
        return defaults.bool(forKey: Self.hasRequestedKey) ? .denied : .notDetermined
    }

    func requestScreenRecordingAccess() {
        defaults.set(true, forKey: Self.hasRequestedKey)
        CGRequestScreenCaptureAccess()
    }
}
