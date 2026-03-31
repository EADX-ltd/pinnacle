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
        XCTAssertEqual(harness.recordingService.stopCount, 1)
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

    func testShortcutRegistrationPublishesBindingsToOverlayService() throws {
        let harness = makeStoreHarness()

        XCTAssertEqual(harness.overlayService.lastShortcutBindings, ShortcutBinding.defaults)
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

    func testToggleRadialControlUpdatesOverlayVisibility() throws {
        let harness = makeStoreHarness()

        XCTAssertEqual(harness.overlayService.lastRadialVisibleValue, true)

        harness.store.send(.toggleRadialControl)
        XCTAssertEqual(harness.overlayService.lastRadialVisibleValue, false)

        harness.store.send(.toggleRadialControl)
        XCTAssertEqual(harness.overlayService.lastRadialVisibleValue, true)
    }

    func testOverlayActionSelectToolRoutesBackToStore() throws {
        let harness = makeStoreHarness()

        harness.overlayService.trigger(.selectTool(.text))

        XCTAssertEqual(harness.store.toolState.activeTool, .text)
    }

    func testUndoCommandRoutesToOverlayService() throws {
        let harness = makeStoreHarness()

        harness.store.send(.undo)

        XCTAssertEqual(harness.overlayService.undoCount, 1)
    }

    func testRedoCommandRoutesToOverlayService() throws {
        let harness = makeStoreHarness()

        harness.store.send(.redo)

        XCTAssertEqual(harness.overlayService.redoCount, 1)
    }

    func testClearAllCommandRoutesToOverlayServiceAsUndoable() throws {
        let harness = makeStoreHarness()

        harness.store.send(.clearAll)

        XCTAssertEqual(harness.overlayService.clearAllInvocations, [true])
    }

    func testOverlayActionUndoRedoClearRoutesBackToStore() throws {
        let harness = makeStoreHarness()

        harness.overlayService.trigger(.undo)
        harness.overlayService.trigger(.redo)
        harness.overlayService.trigger(.clearAll)

        XCTAssertEqual(harness.overlayService.undoCount, 1)
        XCTAssertEqual(harness.overlayService.redoCount, 1)
        XCTAssertEqual(harness.overlayService.clearAllInvocations, [true])
    }

    func testOverlaySceneModelUndoRedoSupportsMixedElementHistory() {
        var scene = OverlaySceneModel()

        let stroke = OverlaySceneElement(kind: .stroke(
            points: [CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 20)],
            width: 4,
            colorHexRGBA: "#FF3B30FF",
            opacity: 1
        ))
        let rectangle = OverlaySceneElement(kind: .rectangle(
            rect: CGRect(x: 40, y: 40, width: 100, height: 60),
            width: 4,
            colorHexRGBA: "#34C759FF",
            opacity: 1
        ))
        let text = OverlaySceneElement(kind: .text(
            text: "Title",
            center: CGPoint(x: 150, y: 140),
            fontSize: 24,
            colorHexRGBA: "#FFFFFFFF",
            opacity: 1
        ))

        scene.commit(stroke)
        scene.commit(rectangle)
        scene.commit(text)
        XCTAssertEqual(scene.elements.map(\.id), [stroke.id, rectangle.id, text.id])

        scene.undo()
        XCTAssertEqual(scene.elements.map(\.id), [stroke.id, rectangle.id])

        scene.undo()
        XCTAssertEqual(scene.elements.map(\.id), [stroke.id])

        scene.redo()
        XCTAssertEqual(scene.elements.map(\.id), [stroke.id, rectangle.id])

        scene.redo()
        XCTAssertEqual(scene.elements.map(\.id), [stroke.id, rectangle.id, text.id])
    }

    func testOverlaySceneModelClearAllIsUndoable() {
        var scene = OverlaySceneModel()
        let arrow = OverlaySceneElement(kind: .arrow(
            start: CGPoint(x: 20, y: 20),
            end: CGPoint(x: 80, y: 80),
            width: 4,
            colorHexRGBA: "#0A84FFFF",
            opacity: 1
        ))
        scene.commit(arrow)
        XCTAssertEqual(scene.elements.count, 1)

        scene.clearAll(allowUndo: true)
        XCTAssertTrue(scene.elements.isEmpty)

        scene.undo()
        XCTAssertEqual(scene.elements.map(\.id), [arrow.id])
    }

    func testOverlaySceneModelEraserRemovesTopmostHitElement() {
        var scene = OverlaySceneModel()
        let lower = OverlaySceneElement(kind: .rectangle(
            rect: CGRect(x: 10, y: 10, width: 80, height: 80),
            width: 4,
            colorHexRGBA: "#34C759FF",
            opacity: 1
        ))
        let upper = OverlaySceneElement(kind: .ellipse(
            rect: CGRect(x: 20, y: 20, width: 80, height: 80),
            width: 4,
            colorHexRGBA: "#AF52DEFF",
            opacity: 1
        ))
        scene.commit(lower)
        scene.commit(upper)

        let removed = scene.eraseTopmostElement(at: CGPoint(x: 40, y: 40))
        XCTAssertTrue(removed)
        XCTAssertEqual(scene.elements.map(\.id), [lower.id])
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
    private(set) var updatedToolState: ToolState?
    private(set) var undoCount = 0
    private(set) var redoCount = 0
    private(set) var clearAllInvocations: [Bool] = []
    private(set) var lastRadialVisibleValue = true
    private(set) var lastShortcutBindings: [ShortcutBinding] = []
    private var commandHandler: (@MainActor (OverlayAction) -> Void)?

    func startOverlay() {
        startCount += 1
    }

    func stopOverlay() {
        stopCount += 1
    }

    func update(toolState: ToolState) {
        updatedToolState = toolState
    }

    func undoLastChange() {
        undoCount += 1
    }

    func redoLastChange() {
        redoCount += 1
    }

    func clearAll(allowUndo: Bool) {
        clearAllInvocations.append(allowUndo)
    }

    func setRadialControlVisible(_ isVisible: Bool) {
        lastRadialVisibleValue = isVisible
    }

    func setShortcutBindings(_ bindings: [ShortcutBinding]) {
        lastShortcutBindings = bindings
    }

    func setCommandHandler(_ handler: @escaping @MainActor (OverlayAction) -> Void) {
        commandHandler = handler
    }

    func trigger(_ action: OverlayAction) {
        commandHandler?(action)
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
