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

    func testToolShortcutActivatesOverlaySelectionBehavior() throws {
        let harness = makeStoreHarness()

        harness.shortcutService.trigger(.selectRectangle)

        XCTAssertEqual(harness.overlayService.activatedTools, [.rectangle])
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

    func testApplyToolOptionsUpdatesToolStateAndPushesToOverlay() throws {
        let harness = makeStoreHarness()
        let newConfig = ToolConfig(colorHexRGBA: "#0A84FFFF", strokeWidth: 8, opacity: 0.9)
        let newOptions = ToolExtendedOptions(lineStyle: .dashed, arrowStyle: .double, textFontDesign: .serif)

        harness.overlayService.trigger(.applyToolOptions(.pen, newConfig, newOptions))

        XCTAssertEqual(harness.store.toolState.configs[.pen], newConfig)
        XCTAssertEqual(harness.store.toolState.extendedOptions[.pen], newOptions)
        XCTAssertEqual(harness.overlayService.updatedToolState?.configs[.pen], newConfig)
    }

    func testToolStateDefaultIncludesExtendedOptionsForAllTools() {
        let state = ToolState.default

        for tool in ToolKind.allCases {
            XCTAssertNotNil(state.extendedOptions[tool], "Missing extendedOptions for \(tool)")
            XCTAssertEqual(state.extendedOptions[tool]?.lineStyle, .solid)
            XCTAssertEqual(state.extendedOptions[tool]?.arrowStyle, .single)
            XCTAssertEqual(state.extendedOptions[tool]?.textFontDesign, .system)
        }
    }

    func testToolExtendedOptionsDefaultValues() {
        let options = ToolExtendedOptions.default
        XCTAssertEqual(options.lineStyle, .solid)
        XCTAssertEqual(options.arrowStyle, .single)
        XCTAssertEqual(options.textFontDesign, .system)
    }

    func testOverlaySceneModelUndoRedoSupportsMixedElementHistory() {
        var scene = OverlaySceneModel()

        let stroke = OverlaySceneElement(kind: .stroke(
            points: [CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 20)],
            width: 4,
            colorHexRGBA: "#FF3B30FF",
            opacity: 1,
            lineStyle: .solid
        ))
        let rectangle = OverlaySceneElement(kind: .rectangle(
            rect: CGRect(x: 40, y: 40, width: 100, height: 60),
            width: 4,
            colorHexRGBA: "#34C759FF",
            opacity: 1,
            lineStyle: .solid
        ))
        let text = OverlaySceneElement(kind: .text(
            text: "Title",
            origin: CGPoint(x: 150, y: 140),
            fontSize: 24,
            colorHexRGBA: "#FFFFFFFF",
            opacity: 1,
            fontDesign: .system
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
            opacity: 1,
            lineStyle: .solid,
            arrowStyle: .single
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
            opacity: 1,
            lineStyle: .solid
        ))
        let upper = OverlaySceneElement(kind: .ellipse(
            rect: CGRect(x: 20, y: 20, width: 80, height: 80),
            width: 4,
            colorHexRGBA: "#AF52DEFF",
            opacity: 1,
            lineStyle: .solid
        ))
        scene.commit(lower)
        scene.commit(upper)

        let removed = scene.eraseTopmostElement(at: CGPoint(x: 40, y: 40))
        XCTAssertTrue(removed)
        XCTAssertEqual(scene.elements.map(\.id), [lower.id])
    }

    func testShiftConstrainedStrokeCommitsStraightPreviewLine() {
        let viewModel = OverlayViewModel()
        viewModel.toolState.activeTool = .pen

        viewModel.handleDragChanged(
            startLocation: CGPoint(x: 10, y: 10),
            location: CGPoint(x: 10, y: 10)
        )
        viewModel.handleDragChanged(
            startLocation: CGPoint(x: 10, y: 10),
            location: CGPoint(x: 60, y: 45),
            isShiftConstrained: true
        )
        viewModel.handleDragEnded(
            startLocation: CGPoint(x: 10, y: 10),
            location: CGPoint(x: 60, y: 45),
            translation: CGSize(width: 50, height: 35),
            isShiftConstrained: true
        )

        guard case let .stroke(points, _, _, _, _) = viewModel.sceneElements.last?.kind else {
            return XCTFail("Expected stroke element")
        }
        XCTAssertEqual(points, [CGPoint(x: 10, y: 10), CGPoint(x: 60, y: 45)])
    }

    func testShiftConstrainedArrowSnapsToNearestFortyFiveDegrees() {
        let viewModel = OverlayViewModel()
        viewModel.toolState.activeTool = .arrow

        viewModel.handleDragChanged(
            startLocation: .zero,
            location: CGPoint(x: 80, y: 20),
            isShiftConstrained: true
        )

        guard case let .arrow(start, end, _, _, _, _, _) = viewModel.previewElement?.kind else {
            return XCTFail("Expected arrow preview")
        }
        XCTAssertEqual(start, .zero)
        XCTAssertEqual(end.y, 0, accuracy: 0.0001)
        XCTAssertEqual(end.x, hypot(80, 20), accuracy: 0.0001)
    }

    func testShiftConstrainedRectanglePreviewsSquare() {
        let viewModel = OverlayViewModel()
        viewModel.toolState.activeTool = .rectangle

        viewModel.handleDragChanged(
            startLocation: CGPoint(x: 10, y: 10),
            location: CGPoint(x: 50, y: 30),
            isShiftConstrained: true
        )

        guard case let .rectangle(rect, _, _, _, _) = viewModel.previewElement?.kind else {
            return XCTFail("Expected rectangle preview")
        }
        XCTAssertEqual(rect.width, rect.height, accuracy: 0.0001)
        XCTAssertEqual(rect.origin.x, 10, accuracy: 0.0001)
        XCTAssertEqual(rect.origin.y, 10, accuracy: 0.0001)
    }

    func testShiftConstrainedEllipseUsesStartPointAsCenter() {
        let viewModel = OverlayViewModel()
        viewModel.toolState.activeTool = .ellipse

        viewModel.handleDragChanged(
            startLocation: CGPoint(x: 100, y: 100),
            location: CGPoint(x: 130, y: 140),
            isShiftConstrained: true
        )

        guard case let .ellipse(rect, _, _, _, _) = viewModel.previewElement?.kind else {
            return XCTFail("Expected ellipse preview")
        }
        XCTAssertEqual(rect.midX, 100, accuracy: 0.0001)
        XCTAssertEqual(rect.midY, 100, accuracy: 0.0001)
        XCTAssertEqual(rect.width, rect.height, accuracy: 0.0001)
    }

    func testCenterTapInPassThroughExitsWithoutSelectingTool() {
        let viewModel = OverlayViewModel()
        viewModel.activateRadialControl()
        viewModel.toolState.activeTool = .rectangle
        viewModel.enterPassThroughMode()

        viewModel.handleCenterTap()

        XCTAssertFalse(viewModel.isPassThroughMode)
        XCTAssertTrue(viewModel.isRadialExpanded)
        XCTAssertNil(viewModel.selectedToolForOptions)
    }

    func testClickingNewTextLocationCommitsCurrentDraftAndStartsAnother() async {
        let viewModel = OverlayViewModel()
        viewModel.toolState.activeTool = .text

        viewModel.handleDragEnded(
            startLocation: CGPoint(x: 40, y: 40),
            location: CGPoint(x: 40, y: 40),
            translation: .zero
        )
        viewModel.textDraft?.text = "First note"

        viewModel.handleDragEnded(
            startLocation: CGPoint(x: 160, y: 120),
            location: CGPoint(x: 160, y: 120),
            translation: .zero
        )

        await Task.yield()

        XCTAssertEqual(viewModel.textItems.count, 1)
        XCTAssertEqual(viewModel.textItems.first?.text, "First note")
        XCTAssertEqual(viewModel.textDraft?.origin, CGPoint(x: 160, y: 120))
        XCTAssertEqual(viewModel.textDraft?.text, "")
    }

    func testActivateToolSelectionExitsPassThroughAndMirrorsToolClick() {
        let viewModel = OverlayViewModel()
        viewModel.activateToolSelection(.pen)
        viewModel.openOptions()
        viewModel.enterPassThroughMode()

        viewModel.activateToolSelection(.eraser)

        XCTAssertFalse(viewModel.isPassThroughMode)
        XCTAssertTrue(viewModel.isRadialExpanded)
        XCTAssertEqual(viewModel.selectedToolForOptions, .eraser)
        XCTAssertFalse(viewModel.isOptionsOpen)
    }

    func testToolStateDefaultToolPresetsMatchRequestedColorsAndSizes() {
        let state = ToolState.default

        XCTAssertEqual(state.configs[.pen]?.colorHexRGBA, "#FFD60AFF")
        XCTAssertEqual(state.configs[.highlighter]?.colorHexRGBA, "#FFD60A66")
        XCTAssertEqual(state.configs[.text]?.colorHexRGBA, "#FFD60AFF")
        XCTAssertEqual(state.configs[.arrow]?.colorHexRGBA, "#0A84FFFF")
        XCTAssertEqual(state.configs[.rectangle]?.colorHexRGBA, "#0A84FFFF")
        XCTAssertEqual(state.configs[.ellipse]?.colorHexRGBA, "#0A84FFFF")
        XCTAssertEqual(state.configs[.pen]?.strokeWidth, 1)
        XCTAssertEqual(state.configs[.arrow]?.strokeWidth, 1)
        XCTAssertEqual(state.configs[.rectangle]?.strokeWidth, 1)
        XCTAssertEqual(state.configs[.ellipse]?.strokeWidth, 1)
        XCTAssertEqual(state.configs[.highlighter]?.strokeWidth, 14)
        XCTAssertEqual(state.configs[.text]?.strokeWidth, 14)
    }

    func testTooltipIncludesShiftHintForConstrainedTool() {
        let viewModel = OverlayViewModel()
        viewModel.shortcutLabelByCommand = [.selectRectangle: "Ctrl+Opt+4"]

        let tooltip = viewModel.tooltip(for: .tool(.rectangle))

        XCTAssertEqual(tooltip, "Rectangle (Ctrl+Opt+4) · Shift: Square")
    }

    func testEnsureInitialRadialPositionPlacesControlOnRightSide() {
        let viewModel = OverlayViewModel()

        viewModel.ensureInitialRadialPosition(in: CGSize(width: 1440, height: 900))

        XCTAssertEqual(viewModel.radialCenter.x, 1220, accuracy: 0.0001)
        XCTAssertEqual(viewModel.radialCenter.y, 220, accuracy: 0.0001)
    }

    func testOverlaySceneElementLineStyleAndArrowStyleStoredPerElement() {
        let dashedArrow = OverlaySceneElement(kind: .arrow(
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 100, y: 0),
            width: 3,
            colorHexRGBA: "#0A84FFFF",
            opacity: 1,
            lineStyle: .dashed,
            arrowStyle: .double
        ))
        if case let .arrow(_, _, _, _, _, lineStyle, arrowStyle) = dashedArrow.kind {
            XCTAssertEqual(lineStyle, .dashed)
            XCTAssertEqual(arrowStyle, .double)
        } else {
            XCTFail("Expected arrow element")
        }

        let dottedStroke = OverlaySceneElement(kind: .stroke(
            points: [.zero, CGPoint(x: 50, y: 50)],
            width: 4,
            colorHexRGBA: "#FF3B30FF",
            opacity: 1,
            lineStyle: .dotted
        ))
        if case let .stroke(_, _, _, _, lineStyle) = dottedStroke.kind {
            XCTAssertEqual(lineStyle, .dotted)
        } else {
            XCTFail("Expected stroke element")
        }
    }

    func testOverlaySceneTextElementStoresFontDesign() {
        let serifText = OverlaySceneElement(kind: .text(
            text: "Hello",
            origin: CGPoint(x: 100, y: 100),
            fontSize: 24,
            colorHexRGBA: "#FFFFFFFF",
            opacity: 1,
            fontDesign: .serif
        ))
        if case let .text(_, _, _, _, _, fontDesign) = serifText.kind {
            XCTAssertEqual(fontDesign, .serif)
        } else {
            XCTFail("Expected text element")
        }
    }

    func testDisplayCoordinateTransformerRoundTripsPointForNegativeOriginDisplay() {
        let transformer = DisplayCoordinateTransformer(
            displayFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        )
        let localPoint = CGPoint(x: 250, y: 400)

        let globalPoint = transformer.localPointToGlobal(localPoint)
        XCTAssertEqual(globalPoint.x, -1670, accuracy: 0.0001)
        XCTAssertEqual(globalPoint.y, 400, accuracy: 0.0001)

        let roundTrip = transformer.globalPointToLocal(globalPoint)
        XCTAssertEqual(roundTrip.x, localPoint.x, accuracy: 0.0001)
        XCTAssertEqual(roundTrip.y, localPoint.y, accuracy: 0.0001)
    }

    func testDisplayCoordinateTransformerConvertsRectsAcrossDisplays() {
        let transformer = DisplayCoordinateTransformer(
            displayFrame: CGRect(x: 1728, y: -200, width: 1728, height: 1117)
        )
        let localRect = CGRect(x: 100, y: 120, width: 400, height: 240)

        let globalRect = transformer.localRectToGlobal(localRect)
        XCTAssertEqual(globalRect.origin.x, 1828, accuracy: 0.0001)
        XCTAssertEqual(globalRect.origin.y, -80, accuracy: 0.0001)
        XCTAssertEqual(globalRect.size.width, 400, accuracy: 0.0001)
        XCTAssertEqual(globalRect.size.height, 240, accuracy: 0.0001)

        let roundTrip = transformer.globalRectToLocal(globalRect)
        XCTAssertEqual(roundTrip.origin.x, localRect.origin.x, accuracy: 0.0001)
        XCTAssertEqual(roundTrip.origin.y, localRect.origin.y, accuracy: 0.0001)
        XCTAssertEqual(roundTrip.size.width, localRect.size.width, accuracy: 0.0001)
        XCTAssertEqual(roundTrip.size.height, localRect.size.height, accuracy: 0.0001)
    }

    func testDisplayDescriptorPreservesMixedScaleAndIdentifier() {
        let descriptor = DisplayDescriptor(
            id: 42,
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            scaleFactor: 2
        )

        XCTAssertEqual(descriptor.id, 42)
        XCTAssertEqual(descriptor.scaleFactor, 2, accuracy: 0.0001)
        XCTAssertEqual(descriptor.frame.width, 1512, accuracy: 0.0001)
        XCTAssertEqual(descriptor.frame.height, 982, accuracy: 0.0001)
    }
}

@MainActor
private func makeStoreHarness(
    shouldRecordingStartThrow: Bool = false,
    shortcutService: SpyShortcutService? = nil,
    preferencesService: UserDefaultsPreferencesService? = nil
) -> StoreHarness {
    let shortcutService = shortcutService ?? SpyShortcutService()
    let preferencesService = preferencesService ?? UserDefaultsPreferencesService(
        defaults: UserDefaults(suiteName: "PinnacleTests") ?? .standard
    )
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
    private(set) var activatedTools: [ToolKind] = []
    private(set) var undoCount = 0
    private(set) var redoCount = 0
    private(set) var clearAllInvocations: [Bool] = []
    private(set) var lastRadialVisibleValue = true
    private(set) var lastShortcutBindings: [ShortcutBinding] = []
    private var commandHandler: (@MainActor (OverlayAction) -> Void)?
    private var errorHandler: (@MainActor (String) -> Void)?

    func startOverlay() {
        startCount += 1
    }

    func stopOverlay() {
        stopCount += 1
    }

    func update(toolState: ToolState) {
        updatedToolState = toolState
    }

    func activateToolSelection(_ tool: ToolKind) {
        activatedTools.append(tool)
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

    func setErrorHandler(_ handler: @escaping @MainActor (String) -> Void) {
        errorHandler = handler
    }

    func trigger(_ action: OverlayAction) {
        commandHandler?(action)
    }

    func triggerError(_ message: String) {
        errorHandler?(message)
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
