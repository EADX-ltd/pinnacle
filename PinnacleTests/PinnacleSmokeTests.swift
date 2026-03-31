import XCTest

@testable import Pinnacle

@MainActor
final class PinnacleSmokeTests: XCTestCase {
    private let suiteName = "PinnacleTests"

    override func tearDown() {
        if let defaults = UserDefaults(suiteName: suiteName) {
            defaults.removePersistentDomain(forName: suiteName)
        }
        super.tearDown()
    }

    func testAppContainerServiceSmokeBehavior() async throws {
        let shortcutService = NoOpShortcutService()
        let overlayService = NoOpOverlayService()
        let recordingService = InMemoryRecordingService()
        let permissionService = NoOpPermissionService()
        let preferencesService = UserDefaultsPreferencesService(
            defaults: UserDefaults(suiteName: suiteName) ?? .standard
        )
        let container = AppContainer(
            shortcutService: shortcutService,
            overlayService: overlayService,
            recordingService: recordingService,
            permissionService: permissionService,
            preferencesService: preferencesService
        )

        XCTAssertFalse(container.recordingService.isRecording)
        try container.recordingService.startRecording()
        XCTAssertTrue(container.recordingService.isRecording)
        try container.recordingService.stopRecording()
        XCTAssertFalse(container.recordingService.isRecording)

        let key = PreferenceKey(name: "tests.smoke.bool", defaultValue: false)
        container.preferencesService.setValue(true, for: key)
        XCTAssertTrue(container.preferencesService.value(for: key))
        container.preferencesService.setValue(false, for: key)

        let status = await container.permissionService.refreshPermissions()
        XCTAssertEqual(status, .notDetermined)
    }

    func testToggleAnnotationTransitionsIdleToAnnotating() throws {
        let harness = makeStoreHarness()

        harness.store.send(.toggleAnnotation)

        XCTAssertEqual(harness.store.sessionMode, .annotating)
        XCTAssertEqual(harness.overlayService.startCount, 1)
        XCTAssertEqual(harness.overlayService.stopCount, 0)
    }

    func testToggleAnnotationTransitionsRecordingToRecordingAndAnnotating() throws {
        let harness = makeStoreHarness()

        harness.store.send(.startRecording)
        harness.store.send(.toggleAnnotation)

        XCTAssertEqual(harness.store.sessionMode, .recordingAndAnnotating)
        XCTAssertEqual(harness.overlayService.startCount, 1)
        XCTAssertEqual(harness.recordingService.startCount, 1)
    }

    func testToggleRecordingIdleToRecordingAndBackToIdle() throws {
        let harness = makeStoreHarness()

        harness.store.send(.toggleRecording)
        XCTAssertEqual(harness.store.sessionMode, .recording)
        XCTAssertEqual(harness.recordingService.startCount, 1)

        harness.store.send(.toggleRecording)
        XCTAssertEqual(harness.store.sessionMode, .idle)
        XCTAssertEqual(harness.recordingService.stopCount, 1)
    }

    func testStopRecordingReturnsToAnnotatingWhenOverlayIsActive() throws {
        let harness = makeStoreHarness()

        harness.store.send(.toggleAnnotation)
        harness.store.send(.startRecording)
        XCTAssertEqual(harness.store.sessionMode, .recordingAndAnnotating)

        harness.store.send(.stopRecording)
        XCTAssertEqual(harness.store.sessionMode, .annotating)
    }

    func testPauseAndResumeRecordingRestoresPreviousMode() throws {
        let harness = makeStoreHarness()
        harness.store.send(.toggleAnnotation)
        harness.store.send(.startRecording)

        harness.store.send(.pauseRecording)
        XCTAssertEqual(harness.store.sessionMode, .paused)

        harness.store.send(.resumeRecording)
        XCTAssertEqual(harness.store.sessionMode, .recordingAndAnnotating)
    }

    func testSendStoresErrorMessageWhenRecordingServiceThrows() throws {
        let harness = makeStoreHarness(shouldRecordingStartThrow: true)

        harness.store.send(.startRecording)

        XCTAssertNotNil(harness.store.lastErrorMessage)
        XCTAssertEqual(harness.store.sessionMode, .idle)
    }

    func testShortcutRegistrationUsesDefaultBindingsWhenStoredBindingsConflict() throws {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let preferencesService = UserDefaultsPreferencesService(defaults: defaults)
        let conflictingBindings = [
            ShortcutBinding(commandID: .toggleAnnotation, key: .a, modifiers: [.control, .option]),
            ShortcutBinding(commandID: .toggleRecording, key: .a, modifiers: [.control, .option])
        ]
        preferencesService.setValue(conflictingBindings, for: AppStore.shortcutBindingsPreferenceKey)

        let shortcutService = SpyShortcutService()
        let harness = makeStoreHarness(
            shortcutService: shortcutService,
            preferencesService: preferencesService
        )
        XCTAssertEqual(harness.store.sessionMode, .idle)

        XCTAssertEqual(shortcutService.lastRegisteredBindings, ShortcutBinding.defaults)
        XCTAssertEqual(
            preferencesService.value(for: AppStore.shortcutBindingsPreferenceKey),
            ShortcutBinding.defaults
        )
    }

    func testShortcutRegistrationPreservesEmptyBindingsWhenNoConflicts() throws {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let preferencesService = UserDefaultsPreferencesService(defaults: defaults)
        preferencesService.setValue([], for: AppStore.shortcutBindingsPreferenceKey)

        let shortcutService = SpyShortcutService()
        _ = makeStoreHarness(
            shortcutService: shortcutService,
            preferencesService: preferencesService
        )

        XCTAssertEqual(shortcutService.lastRegisteredBindings, [])
        XCTAssertEqual(preferencesService.value(for: AppStore.shortcutBindingsPreferenceKey), [])
    }

    func testShortcutCommandMappingTriggersStoreActions() throws {
        let harness = makeStoreHarness()

        harness.shortcutService.trigger(.toggleAnnotation)
        XCTAssertEqual(harness.store.sessionMode, .annotating)

        harness.shortcutService.trigger(.toggleRecording)
        XCTAssertEqual(harness.store.sessionMode, .recordingAndAnnotating)

        harness.shortcutService.trigger(.togglePauseRecording)
        XCTAssertEqual(harness.store.sessionMode, .paused)

        harness.shortcutService.trigger(.togglePauseRecording)
        XCTAssertEqual(harness.store.sessionMode, .recordingAndAnnotating)

        harness.shortcutService.trigger(.selectEraser)
        XCTAssertEqual(harness.store.toolState.activeTool, .eraser)
    }

    func testStopRecordingFromPausedReturnsToIdleWhenPausedFromRecording() throws {
        let harness = makeStoreHarness()
        harness.store.send(.startRecording)
        harness.store.send(.pauseRecording)

        harness.store.send(.stopRecording)

        XCTAssertEqual(harness.store.sessionMode, .idle)
    }

    func testStopRecordingFromPausedReturnsToAnnotatingWhenPausedFromRecordingAndAnnotating() throws {
        let harness = makeStoreHarness()
        harness.store.send(.toggleAnnotation)
        harness.store.send(.startRecording)
        harness.store.send(.pauseRecording)

        harness.store.send(.stopRecording)

        XCTAssertEqual(harness.store.sessionMode, .annotating)
    }
}

@MainActor
private func makeStoreHarness(
    shouldRecordingStartThrow: Bool = false,
    shortcutService: SpyShortcutService = SpyShortcutService(),
    preferencesService: UserDefaultsPreferencesService = UserDefaultsPreferencesService(
        defaults: UserDefaults(suiteName: "PinnacleTests") ?? .standard
    )
) -> StoreHarness {
    let overlayService = SpyOverlayService()
    let recordingService = SpyRecordingService(shouldThrowOnStart: shouldRecordingStartThrow)
    let permissionService = NoOpPermissionService()

    let container = AppContainer(
        shortcutService: shortcutService,
        overlayService: overlayService,
        recordingService: recordingService,
        permissionService: permissionService,
        preferencesService: preferencesService
    )

    return StoreHarness(
        store: AppStore(container: container),
        shortcutService: shortcutService,
        overlayService: overlayService,
        recordingService: recordingService
    )
}

@MainActor
private struct StoreHarness {
    let store: AppStore
    let shortcutService: SpyShortcutService
    let overlayService: SpyOverlayService
    let recordingService: SpyRecordingService
}

@MainActor
private final class SpyOverlayService: OverlayService {
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func startOverlay() {
        startCount += 1
    }

    func stopOverlay() {
        stopCount += 1
    }
}

@MainActor
private final class SpyRecordingService: RecordingService {
    private(set) var isRecording = false
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private let shouldThrowOnStart: Bool

    init(shouldThrowOnStart: Bool = false) {
        self.shouldThrowOnStart = shouldThrowOnStart
    }

    func startRecording() throws {
        if shouldThrowOnStart {
            throw RecordingStartError.failed
        }
        isRecording = true
        startCount += 1
    }

    func stopRecording() throws {
        isRecording = false
        stopCount += 1
    }
}

private enum RecordingStartError: Error {
    case failed
}

@MainActor
private final class SpyShortcutService: ShortcutService {
    private(set) var lastRegisteredBindings: [ShortcutBinding] = []
    private var handler: (@MainActor (ShortcutCommandID) -> Void)?

    func register(bindings: [ShortcutBinding], handler: @escaping @MainActor (ShortcutCommandID) -> Void) throws {
        lastRegisteredBindings = bindings
        self.handler = handler
    }

    func unregisterAll() throws {
        handler = nil
        lastRegisteredBindings = []
    }

    func trigger(_ command: ShortcutCommandID) {
        handler?(command)
    }
}
