import Combine
import Foundation
import SwiftUI

// Single source of truth for the radial control. Replaces four
// previously-decoupled bools (`isRadialExpanded`, `isOptionsOpen`,
// `isPassThroughMode`, `selectedToolForOptions`) so impossible
// combinations (e.g. options open while collapsed) are unrepresentable.
enum RadialState: Equatable {
    case collapsed
    case expanded(selectedToolForOptions: ToolKind?)
    case optionsOpen(ToolKind)
    case passThrough
}

@MainActor
final class OverlayViewModel: ObservableObject {
    enum RadialItem: Identifiable, Equatable {
        case tool(ToolKind)
        case action(OverlayAction)

        var id: String {
            switch self {
            case let .tool(tool): return "tool.\(tool.rawValue)"
            case let .action(action): return "action.\(action.id)"
            }
        }
    }

    @Published var toolState: ToolState = .default
    @Published var sceneElements: [OverlaySceneElement] = []
    @Published var previewElement: OverlaySceneElement?
    @Published var textItems: [OverlayTextItem] = []
    @Published var isOverlayVisible = false
    @Published var isRadialControlEnabled = true
    @Published var radialState: RadialState = .collapsed
    @Published var pendingConfig: ToolConfig = ToolState.default.configs[.pen]!
    @Published var pendingExtendedOptions: ToolExtendedOptions = .default
    @Published var radialCenter = CGPoint(x: 220, y: 220)
    @Published var shortcutLabelByCommand: [ShortcutCommandID: String] = [:]

    let textEditing = TextEditingViewModel()

    var textDraft: TextDraft? {
        get { textEditing.textDraft }
        set { textEditing.textDraft = newValue }
    }

    var commandHandler: (@MainActor (OverlayAction) -> Void)?
    var strokeDurationRecorder: ((Double) -> Void)?
    var onTextEditingActive: ((Bool) -> Void)?
    var onPassThroughModeChanged: ((Bool) -> Void)?

    private var scene = OverlaySceneModel()
    private var drawingStartPoint: CGPoint?
    private var currentStrokePoints: [CGPoint] = []
    private var strokeStartTime: Date?
    private let radialEdgeInset: CGFloat = 56
    private var hasInitializedRadialPosition = false
    private var textEditingCancellable: AnyCancellable?

    init() {
        textEditing.configForActiveToolProvider = { [weak self] in
            guard let self else { return nil }
            return toolState.configs[toolState.activeTool]
        }
        textEditing.extendedOptionsForActiveToolProvider = { [weak self] in
            guard let self else { return nil }
            return toolState.extendedOptions[toolState.activeTool]
        }
        textEditing.onCommit = { [weak self] text, origin, config, extOpts in
            self?.commitTextElement(text: text, origin: origin, config: config, extOpts: extOpts)
        }
        textEditing.onEditingActiveChanged = { [weak self] active in
            self?.onTextEditingActive?(active)
        }
        textEditingCancellable = textEditing.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var isRadialExpanded: Bool {
        switch radialState {
        case .expanded, .optionsOpen: return true
        case .collapsed, .passThrough: return false
        }
    }

    var isOptionsOpen: Bool {
        if case .optionsOpen = radialState { return true }
        return false
    }

    var isPassThroughMode: Bool {
        if case .passThrough = radialState { return true }
        return false
    }

    var selectedToolForOptions: ToolKind? {
        switch radialState {
        case let .expanded(tool): return tool
        case let .optionsOpen(tool): return tool
        case .collapsed, .passThrough: return nil
        }
    }

    var activeConfig: ToolConfig {
        toolState.configs[toolState.activeTool] ?? ToolState.default.configs[.pen] ?? ToolConfig(colorHexRGBA: "#FFD60AFF", strokeWidth: 1, opacity: 1)
    }

    var activeExtendedOptions: ToolExtendedOptions {
        toolState.extendedOptions[toolState.activeTool] ?? .default
    }

    // Snapshot config used while text is being edited – prevents live changes
    // from options panel affecting the in-progress text element.
    var textDraftActiveConfig: ToolConfig {
        textEditing.textDraftConfig ?? activeConfig
    }

    var textDraftActiveExtendedOptions: ToolExtendedOptions {
        textEditing.textDraftExtendedOptions ?? activeExtendedOptions
    }

    var hudText: String {
        toolState.activeTool.rawValue.capitalized
    }

    var hudColor: Color {
        Color(hexRGBA: activeConfig.colorHexRGBA)
    }

    var radialPrimaryItems: [RadialItem] {
        [
            .tool(.pen),
            .tool(.highlighter),
            .tool(.arrow),
            .tool(.rectangle),
            .tool(.ellipse),
            .tool(.text),
            .tool(.eraser),
            .action(.undo),
            .action(.redo),
            .action(.clearAll)
        ]
    }

    // Coordinate contract: `startLocation`/`location` are GLOBAL points already
    // produced by `DisplayCoordinateTransformer.localPointToGlobal`. The view
    // model stores everything in global space; only `OverlayRootView` converts
    // back to local space for rendering via `globalPointToLocal`. Mixing the
    // two spaces silently shifts annotations on multi-display / scaled setups.
    func handleDragChanged(startLocation: CGPoint, location: CGPoint, isShiftConstrained: Bool = false) {
        switch toolState.activeTool {
        case .pen, .highlighter:
            handleStrokeDragChanged(startLocation: startLocation, location: location, isShiftConstrained: isShiftConstrained)
        case .arrow, .rectangle, .ellipse:
            handleShapeDragChanged(startLocation: startLocation, location: location, isShiftConstrained: isShiftConstrained)
        case .eraser:
            _ = scene.eraseTopmostElement(at: location)
            syncSceneState()
        case .text:
            break
        }
    }

    func handleDragEnded(startLocation: CGPoint, location: CGPoint, translation: CGSize, isShiftConstrained: Bool = false) {
        switch toolState.activeTool {
        case .pen, .highlighter:
            handleStrokeDragEnded(startLocation: startLocation, location: location, isShiftConstrained: isShiftConstrained)
        case .arrow, .rectangle, .ellipse:
            handleShapeDragEnded(translation: translation)
        case .text:
            if translation.length <= 6 {
                queueTextEditing(at: location)
            }
        case .eraser:
            break
        }
        drawingStartPoint = nil
        previewElement = nil
    }

    func commitTextDraft() {
        textEditing.commitTextDraft()
    }

    private func commitTextElement(text: String, origin: CGPoint, config: ToolConfig, extOpts: ToolExtendedOptions) {
        let element = OverlaySceneElement(
            kind: .text(
                text: text,
                origin: origin,
                fontSize: CGFloat(config.strokeWidth),
                colorHexRGBA: config.colorHexRGBA,
                opacity: config.opacity,
                fontDesign: extOpts.textFontDesign
            )
        )
        scene.commit(element)
        syncSceneState()
    }

    func undoLastChange() {
        scene.undo()
        if textDraft != nil { cancelTextDraft() }
        syncSceneState()
    }

    func redoLastChange() {
        scene.redo()
        if textDraft != nil { cancelTextDraft() }
        syncSceneState()
    }

    func clearAll(allowUndo: Bool) {
        scene.clearAll(allowUndo: allowUndo)
        if textDraft != nil { cancelTextDraft() }
        syncSceneState()
    }

    func activateRadialControl() {
        guard isRadialControlEnabled else { return }
        if case .collapsed = radialState {
            radialState = .expanded(selectedToolForOptions: nil)
        }
    }

    func collapseRadialControl() {
        radialState = .collapsed
    }

    func openOptions() {
        guard case let .expanded(maybeTool) = radialState,
              let tool = maybeTool,
              tool.hasConfigurableOptions else { return }
        pendingConfig = toolState.configs[tool] ?? ToolState.default.configs[tool] ?? ToolState.default.configs[.pen] ?? ToolConfig(colorHexRGBA: "#FFD60AFF", strokeWidth: 1, opacity: 1)
        pendingExtendedOptions = toolState.extendedOptions[tool] ?? .default
        radialState = .optionsOpen(tool)
    }

    func confirmOptions() {
        guard case let .optionsOpen(tool) = radialState else { return }
        toolState.configs[tool] = pendingConfig
        toolState.extendedOptions[tool] = pendingExtendedOptions
        commandHandler?(.applyToolOptions(tool, pendingConfig, pendingExtendedOptions))
        radialState = .expanded(selectedToolForOptions: tool)
    }

    func cancelOptions() {
        if case let .optionsOpen(tool) = radialState {
            radialState = .expanded(selectedToolForOptions: tool)
        }
    }

    func toggleOptions() {
        if isOptionsOpen { cancelOptions() } else { openOptions() }
    }

    func handleCenterTap() {
        switch radialState {
        case .passThrough:
            exitPassThroughMode()
            activateRadialControl()
        case let .expanded(maybeTool):
            if let tool = maybeTool, tool.hasConfigurableOptions {
                toggleOptions()
            } else {
                collapseRadialControl()
            }
        case .optionsOpen:
            cancelOptions()
        case .collapsed:
            activateRadialControl()
        }
    }

    func moveRadialControl(to location: CGPoint, in size: CGSize) {
        let minX: CGFloat = radialEdgeInset
        let minY: CGFloat = radialEdgeInset
        let maxX = Swift.max(minX, size.width - radialEdgeInset)
        let maxY = Swift.max(minY, size.height - radialEdgeInset)
        let clamped = CGPoint(
            x: Swift.min(Swift.max(location.x, minX), maxX),
            y: Swift.min(Swift.max(location.y, minY), maxY)
        )
        radialCenter = clamped
    }

    func ensureInitialRadialPosition(in size: CGSize) {
        guard !hasInitializedRadialPosition else { return }
        hasInitializedRadialPosition = true
        moveRadialControl(
            to: CGPoint(x: size.width - 220, y: 220),
            in: size
        )
    }

    func selectPrimaryItem(_ item: RadialItem) {
        switch item {
        case let .tool(tool):
            activateToolSelection(tool)
            commandHandler?(.selectTool(tool))
        case let .action(action):
            if isPassThroughMode { exitPassThroughMode() }
            radialState = .expanded(selectedToolForOptions: nil)
            commandHandler?(action)
        }
    }

    func activateToolSelection(_ tool: ToolKind) {
        if isPassThroughMode { exitPassThroughMode() }
        // Preserve open options panel only if the same tool is being re-selected.
        if case let .optionsOpen(current) = radialState, current == tool {
            return
        }
        radialState = .expanded(selectedToolForOptions: tool)
    }

    func tooltip(for item: RadialItem) -> String {
        switch item {
        case let .tool(tool):
            let command = tool.shortcutCommandID
            var text = "\(tool.rawValue.capitalized) (\(shortcutLabelByCommand[command] ?? "Unbound"))"
            if let shiftHint = shiftHint(for: tool) {
                text += " · Shift: \(shiftHint)"
            }
            return text
        case let .action(action):
            return "\(action.label) (\(shortcutLabelByCommand[action.shortcutCommandID] ?? "Unbound"))"
        }
    }

    var hudTooltip: String {
        let command = toolState.activeTool.shortcutCommandID
        var text = "\(toolState.activeTool.rawValue.capitalized) (\(shortcutLabelByCommand[command] ?? "Unbound"))"
        if let shiftHint = shiftHint(for: toolState.activeTool) {
            text += " · Shift: \(shiftHint)"
        }
        return text
    }

    func enterPassThroughMode() {
        guard !isPassThroughMode else { return }
        radialState = .passThrough
        onPassThroughModeChanged?(true)
    }

    func exitPassThroughMode() {
        guard isPassThroughMode else { return }
        radialState = .collapsed
        onPassThroughModeChanged?(false)
    }

    func cancelTextDraft() {
        textEditing.cancelTextDraft()
    }

    private func queueTextEditing(at point: CGPoint) {
        textEditing.queueTextEditing(at: point)
    }

    private func handleStrokeDragChanged(startLocation: CGPoint, location: CGPoint, isShiftConstrained: Bool) {
        if currentStrokePoints.isEmpty {
            strokeStartTime = Date()
            currentStrokePoints = [startLocation]
        }

        let start = currentStrokePoints.first ?? startLocation
        let previewPoints: [CGPoint]
        if isShiftConstrained {
            previewPoints = [start, location]
        } else {
            if currentStrokePoints.last != location {
                currentStrokePoints.append(location)
            }
            previewPoints = currentStrokePoints
        }

        previewElement = OverlaySceneElement(
            kind: .stroke(
                points: previewPoints,
                width: CGFloat(activeConfig.strokeWidth),
                colorHexRGBA: activeConfig.colorHexRGBA,
                opacity: activeConfig.opacity,
                lineStyle: activeExtendedOptions.lineStyle
            )
        )
    }

    private func handleStrokeDragEnded(startLocation: CGPoint, location: CGPoint, isShiftConstrained: Bool) {
        guard !currentStrokePoints.isEmpty || isShiftConstrained else { return }
        var points = isShiftConstrained
            ? [currentStrokePoints.first ?? startLocation, location]
            : currentStrokePoints
        if points.count == 1, let point = points.first {
            points.append(point)
        }
        let element = OverlaySceneElement(
            kind: .stroke(
                points: points,
                width: CGFloat(activeConfig.strokeWidth),
                colorHexRGBA: activeConfig.colorHexRGBA,
                opacity: activeConfig.opacity,
                lineStyle: activeExtendedOptions.lineStyle
            )
        )
        scene.commit(element)
        if let strokeStartTime {
            let ms = Date().timeIntervalSince(strokeStartTime) * 1000
            strokeDurationRecorder?(ms)
        }
        currentStrokePoints.removeAll()
        strokeStartTime = nil
        syncSceneState()
    }

    private func handleShapeDragChanged(startLocation: CGPoint, location: CGPoint, isShiftConstrained: Bool) {
        if drawingStartPoint == nil {
            drawingStartPoint = startLocation
        }
        let start = drawingStartPoint ?? startLocation
        let extOpts = activeExtendedOptions
        switch toolState.activeTool {
        case .arrow:
            let end = constrainedArrowEndPoint(start: start, location: location, isShiftConstrained: isShiftConstrained)
            previewElement = OverlaySceneElement(
                kind: .arrow(
                    start: start,
                    end: end,
                    width: CGFloat(activeConfig.strokeWidth),
                    colorHexRGBA: activeConfig.colorHexRGBA,
                    opacity: activeConfig.opacity,
                    lineStyle: extOpts.lineStyle,
                    arrowStyle: extOpts.arrowStyle
                )
            )
        case .rectangle:
            let rect = rectangleRect(start: start, location: location, isShiftConstrained: isShiftConstrained)
            previewElement = OverlaySceneElement(
                kind: .rectangle(
                    rect: rect,
                    width: CGFloat(activeConfig.strokeWidth),
                    colorHexRGBA: activeConfig.colorHexRGBA,
                    opacity: activeConfig.opacity,
                    lineStyle: extOpts.lineStyle
                )
            )
        case .ellipse:
            let rect = ellipseRect(start: start, location: location, isShiftConstrained: isShiftConstrained)
            previewElement = OverlaySceneElement(
                kind: .ellipse(
                    rect: rect,
                    width: CGFloat(activeConfig.strokeWidth),
                    colorHexRGBA: activeConfig.colorHexRGBA,
                    opacity: activeConfig.opacity,
                    lineStyle: extOpts.lineStyle
                )
            )
        case .pen, .highlighter, .text, .eraser:
            break
        }
    }

    private func handleShapeDragEnded(translation: CGSize) {
        if translation.length < 2 { return }
        guard let previewElement else { return }
        scene.commit(previewElement)
        syncSceneState()
    }

    private func constrainedArrowEndPoint(start: CGPoint, location: CGPoint, isShiftConstrained: Bool) -> CGPoint {
        guard isShiftConstrained else { return location }

        let deltaX = location.x - start.x
        let deltaY = location.y - start.y
        let distance = hypot(deltaX, deltaY)
        guard distance > 0 else { return location }

        let snappedAngle = (atan2(deltaY, deltaX) / (.pi / 4)).rounded() * (.pi / 4)
        return CGPoint(
            x: start.x + cos(snappedAngle) * distance,
            y: start.y + sin(snappedAngle) * distance
        )
    }

    private func rectangleRect(start: CGPoint, location: CGPoint, isShiftConstrained: Bool) -> CGRect {
        guard isShiftConstrained else {
            return CGRect.normalized(from: start, to: location)
        }

        let deltaX = location.x - start.x
        let deltaY = location.y - start.y
        let side = max(abs(deltaX), abs(deltaY))
        let end = CGPoint(
            x: start.x + side * deltaX.signumOrPositive,
            y: start.y + side * deltaY.signumOrPositive
        )
        return CGRect.normalized(from: start, to: end)
    }

    private func ellipseRect(start: CGPoint, location: CGPoint, isShiftConstrained: Bool) -> CGRect {
        guard isShiftConstrained else {
            return CGRect.normalized(from: start, to: location)
        }

        let radius = hypot(location.x - start.x, location.y - start.y)
        return CGRect(
            x: start.x - radius,
            y: start.y - radius,
            width: radius * 2,
            height: radius * 2
        )
    }

    private func shiftHint(for tool: ToolKind) -> String? {
        switch tool {
        case .pen, .highlighter:
            return "Straight line"
        case .arrow:
            return "Snap 45°"
        case .rectangle:
            return "Square"
        case .ellipse:
            return "Circle from center"
        case .text, .eraser:
            return nil
        }
    }

    private func syncSceneState() {
        sceneElements = scene.elements
        textItems = scene.elements.compactMap { element in
            guard case let .text(text, origin, fontSize, colorHexRGBA, opacity, fontDesign) = element.kind else {
                return nil
            }
            return OverlayTextItem(
                id: element.id,
                text: text,
                origin: origin,
                fontSize: fontSize,
                colorHexRGBA: colorHexRGBA,
                opacity: opacity,
                fontDesign: fontDesign
            )
        }
    }
}

extension CGSize {
    var length: CGFloat {
        sqrt((width * width) + (height * height))
    }
}

private extension CGFloat {
    var signumOrPositive: CGFloat {
        self < 0 ? -1 : 1
    }
}
