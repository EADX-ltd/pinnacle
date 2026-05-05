import CoreGraphics
import Foundation

struct SystemPermissionService: PermissionService {
    func refreshPermissions() async -> PermissionStatus {
        CGPreflightScreenCaptureAccess() ? .granted : .notDetermined
    }

    func requestScreenRecordingAccess() {
        CGRequestScreenCaptureAccess()
    }
}
