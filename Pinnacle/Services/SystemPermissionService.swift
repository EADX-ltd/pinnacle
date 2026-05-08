import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Reports the actual usable Screen Recording permission state.
///
/// `CGPreflightScreenCaptureAccess` is documented as the canonical TCC check,
/// but in practice it returns `false` even when access is granted whenever the
/// running binary's code-signature hash differs from the one TCC recorded the
/// grant against — the typical case for ad-hoc-signed dev builds across
/// rebuilds. We therefore probe with `SCShareableContent`, which is what the
/// recording engine actually relies on. Falling back to the local
/// `hasRequested` flag lets us distinguish "denied" from "not yet asked" when
/// the probe genuinely fails.
final class SystemPermissionService: PermissionService {
    private static let hasRequestedKey = "permissions.screenRecording.hasRequested"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func refreshPermissions() async -> PermissionStatus {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            return .granted
        } catch {
            // Probe failed — user lacks usable access. Differentiate denied vs
            // not-yet-determined via the local prompt history flag, since the
            // OS APIs don't expose that distinction.
            return defaults.bool(forKey: Self.hasRequestedKey) ? .denied : .notDetermined
        }
    }

    func requestScreenRecordingAccess() {
        defaults.set(true, forKey: Self.hasRequestedKey)
        CGRequestScreenCaptureAccess()
    }
}
