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

    var activeConfig: ToolConfig {
        toolState.configs[toolState.activeTool] ?? ToolConfig(colorHexRGBA: "#FF3B30FF", strokeWidth: 4, opacity: 1)
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

    func handleDragChanged(startLocation: CGPoint, location: CGPoint) {
        switch toolState.activeTool {
        case .pen, .highlighter:
            handleStrokeDragChanged(location)
        case .arrow, .rectangle, .ellipse:
            handleShapeDragChanged(startLocation: startLocation, location: location)
        case .eraser:
            _ = scene.eraseTopmostElement(at: location)
            syncSceneState()
        case .text:
            break
        }
    }

    func handleDragEnded(startLocation: CGPoint, location: CGPoint, translation: CGSize) {
        switch toolState.activeTool {
        case .pen, .highlighter:
            handleStrokeDragEnded()
        case .arrow, .rectangle, .ellipse:
            handleShapeDragEnded(translation: translation)
        case .text:
            if translation.length <= 6 {
                beginTextEditing(at: location)
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
                center: textDraft.center,
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
        pendingConfig = toolState.configs[tool] ?? ToolConfig(colorHexRGBA: "#FF3B30FF", strokeWidth: 4, opacity: 1)
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

    func selectPrimaryItem(_ item: RadialItem) {
        if isPassThroughMode { exitPassThroughMode() }
        activateRadialControl()
        switch item {
        case let .tool(tool):
            if tool != selectedToolForOptions { isOptionsOpen = false }
            selectedToolForOptions = tool
            commandHandler?(.selectTool(tool))
        case let .action(action):
            selectedToolForOptions = nil
            isOptionsOpen = false
            commandHandler?(action)
        }
    }

    func tooltip(for item: RadialItem) -> String {
        switch item {
        case let .tool(tool):
            let command = tool.shortcutCommandID
            return "\(tool.rawValue.capitalized) (\(shortcutLabelByCommand[command] ?? "Unbound"))"
        case let .action(action):
            return "\(action.label) (\(shortcutLabelByCommand[action.shortcutCommandID] ?? "Unbound"))"
        }
    }

    var hudTooltip: String {
        let command = toolState.activeTool.shortcutCommandID
        return "\(toolState.activeTool.rawValue.capitalized) (\(shortcutLabelByCommand[command] ?? "Unbound"))"
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

    private func beginTextEditing(at point: CGPoint) {
        commitTextDraft()
        textDraftConfig = toolState.configs[toolState.activeTool]
        textDraftExtendedOptions = toolState.extendedOptions[toolState.activeTool]
        textDraft = TextDraft(text: "", center: point)
        onTextEditingActive?(true)
    }

    private func handleStrokeDragChanged(_ location: CGPoint) {
        if currentStrokePoints.isEmpty {
            strokeStartTime = Date()
        }
        currentStrokePoints.append(location)
        previewElement = OverlaySceneElement(
            kind: .stroke(
                points: currentStrokePoints,
                width: CGFloat(activeConfig.strokeWidth),
                colorHexRGBA: activeConfig.colorHexRGBA,
                opacity: activeConfig.opacity,
                lineStyle: activeExtendedOptions.lineStyle
            )
        )
    }

    private func handleStrokeDragEnded() {
        guard !currentStrokePoints.isEmpty else { return }
        var points = currentStrokePoints
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

    private func handleShapeDragChanged(startLocation: CGPoint, location: CGPoint) {
        if drawingStartPoint == nil {
            drawingStartPoint = startLocation
        }
        let start = drawingStartPoint ?? startLocation
        let end = location
        let extOpts = activeExtendedOptions
        switch toolState.activeTool {
        case .arrow:
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
            previewElement = OverlaySceneElement(
                kind: .rectangle(
                    rect: CGRect.normalized(from: start, to: end),
                    width: CGFloat(activeConfig.strokeWidth),
                    colorHexRGBA: activeConfig.colorHexRGBA,
                    opacity: activeConfig.opacity,
                    lineStyle: extOpts.lineStyle
                )
            )
        case .ellipse:
            previewElement = OverlaySceneElement(
                kind: .ellipse(
                    rect: CGRect.normalized(from: start, to: end),
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

    private func syncSceneState() {
        sceneElements = scene.elements
        textItems = scene.elements.compactMap { element in
            guard case let .text(text, center, fontSize, colorHexRGBA, opacity, fontDesign) = element.kind else {
                return nil
            }
            return OverlayTextItem(
                id: element.id,
                text: text,
                center: center,
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
