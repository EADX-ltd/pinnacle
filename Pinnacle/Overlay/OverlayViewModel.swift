import Combine
import Foundation
import SwiftUI

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
    @Published var textDraft: TextDraft?
    @Published var isOverlayVisible = false
    @Published var isRadialControlEnabled = true
    @Published var isRadialExpanded = false
    @Published var isPassThroughMode = false
    @Published var selectedToolForOptions: ToolKind?
    @Published var isOptionsOpen = false
    @Published var pendingConfig: ToolConfig = ToolState.default.configs[.pen]!
    @Published var pendingExtendedOptions: ToolExtendedOptions = .default
    @Published var radialCenter = CGPoint(x: 220, y: 220)
    @Published var shortcutLabelByCommand: [ShortcutCommandID: String] = [:]

    var commandHandler: (@MainActor (OverlayAction) -> Void)?
    var strokeDurationRecorder: ((Double) -> Void)?
    var onTextEditingActive: ((Bool) -> Void)?
    var onPassThroughModeChanged: ((Bool) -> Void)?

    private var scene = OverlaySceneModel()
    private var drawingStartPoint: CGPoint?
    private var currentStrokePoints: [CGPoint] = []
    private var strokeStartTime: Date?
    private var textDraftConfig: ToolConfig?
    private var textDraftExtendedOptions: ToolExtendedOptions?
    private let radialEdgeInset: CGFloat = 56
    private var hasInitializedRadialPosition = false

    var activeConfig: ToolConfig {
        toolState.configs[toolState.activeTool] ?? ToolState.default.configs[.pen] ?? ToolConfig(colorHexRGBA: "#FFD60AFF", strokeWidth: 1, opacity: 1)
    }

    var activeExtendedOptions: ToolExtendedOptions {
        toolState.extendedOptions[toolState.activeTool] ?? .default
    }

    // Snapshot config used while text is being edited – prevents live changes
    // from options panel affecting the in-progress text element.
    var textDraftActiveConfig: ToolConfig {
        textDraftConfig ?? activeConfig
    }

    var textDraftActiveExtendedOptions: ToolExtendedOptions {
        textDraftExtendedOptions ?? activeExtendedOptions
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
        guard let textDraft else { return }
        let trimmed = textDraft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = textDraftConfig ?? activeConfig
        let extOpts = textDraftExtendedOptions ?? activeExtendedOptions
        self.textDraft = nil
        textDraftConfig = nil
        textDraftExtendedOptions = nil
        onTextEditingActive?(false)
        guard !trimmed.isEmpty else { return }
        let element = OverlaySceneElement(
            kind: .text(
                text: trimmed,
                origin: textDraft.origin,
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
        if !isRadialExpanded { isRadialExpanded = true }
    }

    func collapseRadialControl() {
        isRadialExpanded = false
        selectedToolForOptions = nil
        isOptionsOpen = false
    }

    func openOptions() {
        guard isRadialExpanded,
              let tool = selectedToolForOptions,
              tool.hasConfigurableOptions else { return }
        pendingConfig = toolState.configs[tool] ?? ToolState.default.configs[tool] ?? ToolState.default.configs[.pen] ?? ToolConfig(colorHexRGBA: "#FFD60AFF", strokeWidth: 1, opacity: 1)
        pendingExtendedOptions = toolState.extendedOptions[tool] ?? .default
        isOptionsOpen = true
    }

    func confirmOptions() {
        guard let tool = selectedToolForOptions else {
            isOptionsOpen = false
            return
        }
        toolState.configs[tool] = pendingConfig
        toolState.extendedOptions[tool] = pendingExtendedOptions
        commandHandler?(.applyToolOptions(tool, pendingConfig, pendingExtendedOptions))
        isOptionsOpen = false
    }

    func cancelOptions() {
        isOptionsOpen = false
    }

    func toggleOptions() {
        if isOptionsOpen { cancelOptions() } else { openOptions() }
    }

    func handleCenterTap() {
        if isPassThroughMode {
            exitPassThroughMode()
            activateRadialControl()
            return
        }

        if isRadialExpanded {
            if let tool = selectedToolForOptions, tool.hasConfigurableOptions {
                toggleOptions()
            } else {
                collapseRadialControl()
            }
        } else {
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
            activateRadialControl()
            selectedToolForOptions = nil
            isOptionsOpen = false
            commandHandler?(action)
        }
    }

    func activateToolSelection(_ tool: ToolKind) {
        if isPassThroughMode { exitPassThroughMode() }
        activateRadialControl()
        if tool != selectedToolForOptions { isOptionsOpen = false }
        selectedToolForOptions = tool
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
        isPassThroughMode = true
        selectedToolForOptions = nil
        isOptionsOpen = false
        onPassThroughModeChanged?(true)
    }

    func exitPassThroughMode() {
        guard isPassThroughMode else { return }
        isPassThroughMode = false
        onPassThroughModeChanged?(false)
    }

    func cancelTextDraft() {
        textDraft = nil
        textDraftConfig = nil
        textDraftExtendedOptions = nil
        onTextEditingActive?(false)
    }

    private func queueTextEditing(at point: CGPoint) {
        let needsDeferredRestart = textDraft != nil
        if needsDeferredRestart {
            commitTextDraft()
            DispatchQueue.main.async { [weak self] in
                self?.beginTextEditing(at: point)
            }
            return
        }
        beginTextEditing(at: point)
    }

    private func beginTextEditing(at point: CGPoint) {
        textDraftConfig = toolState.configs[toolState.activeTool]
        textDraftExtendedOptions = toolState.extendedOptions[toolState.activeTool]
        textDraft = TextDraft(text: "", origin: point)
        onTextEditingActive?(true)
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
