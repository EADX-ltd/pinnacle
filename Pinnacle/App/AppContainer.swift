import Foundation
// Module boundaries:
// - App: composition root, state orchestration, and dependency graph.
// - Domain: pure models and business rules.
// - Services: protocol abstractions for system IO and persistence.
// - Overlay/Recording: rendering and capture engines behind Services.
// - Settings: UI and logic for user-configurable preferences.
@MainActor
final class AppContainer {
    let shortcutService: ShortcutService
    let overlayService: OverlayService
    let recordingService: RecordingService
    let permissionService: PermissionService
    let preferencesService: PreferencesService
    init(
        shortcutService: ShortcutService,
        overlayService: OverlayService,
        recordingService: RecordingService,
        permissionService: PermissionService,
        preferencesService: PreferencesService
    ) {
        self.shortcutService = shortcutService
        self.overlayService = overlayService
        self.recordingService = recordingService
        self.permissionService = permissionService
        self.preferencesService = preferencesService
    }
    static let live = AppContainer(
        shortcutService: AppKitShortcutService(),
        overlayService: NoOpOverlayService(),
        recordingService: InMemoryRecordingService(),
        permissionService: NoOpPermissionService(),
        preferencesService: UserDefaultsPreferencesService()
    )
}
