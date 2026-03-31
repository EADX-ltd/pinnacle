import AppKit
import Combine
import Foundation
import SwiftUI
import os
@MainActor
final class AppKitOverlayService: OverlayService {
    private let logger = Logger(subsystem: "Pinnacle", category: "Overlay")
    private let viewModel = OverlayViewModel()
    private var overlayPanel: OverlayPanel?
    init() {
        viewModel.strokeDurationRecorder = { [logger] durationMs in
            logger.log("Pen stroke duration baseline: \(durationMs, format: .fixed(precision: 2), privacy: .public)ms")
        }
    }
    func startOverlay() {
        if let overlayPanel, overlayPanel.frame.isEmpty {
            self.overlayPanel = nil
            logger.warning("Discarding cached zero-sized overlay panel and attempting recreation")
        }
        if overlayPanel == nil {
            overlayPanel = makeOverlayPanel()
        }
        guard let overlayPanel else {
            logger.error("No screen available - overlay panel cannot be created")
            return
        }
        viewModel.isOverlayVisible = true
        overlayPanel.orderFrontRegardless()
        logger.log("Overlay started")
    }
    func stopOverlay() {
        viewModel.isOverlayVisible = false
        viewModel.collapseRadialControl()
        overlayPanel?.orderOut(nil)
        logger.log("Overlay stopped")
    }
    func update(toolState: ToolState) {
        viewModel.toolState = toolState
    }
    func undoLastChange() {
        viewModel.undoLastChange()
    }
    func redoLastChange() {
        viewModel.redoLastChange()
    }
    func clearAll(allowUndo: Bool) {
        viewModel.clearAll(allowUndo: allowUndo)
    }
    func setRadialControlVisible(_ isVisible: Bool) {
        viewModel.isRadialControlEnabled = isVisible
        if !isVisible {
            viewModel.collapseRadialControl()
        }
    }
    func setShortcutBindings(_ bindings: [ShortcutBinding]) {
        viewModel.shortcutLabelByCommand = Dictionary(
            uniqueKeysWithValues: bindings.map { ($0.commandID, $0.displayText) }
        )
    }
    func setCommandHandler(_ handler: @escaping @MainActor (OverlayAction) -> Void) {
        viewModel.commandHandler = handler
    }
    private func makeOverlayPanel() -> OverlayPanel? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            overlayPanel = nil
            return nil
        }
        let frame = screen.frame
        let panel = OverlayPanel(contentRect: frame)
        panel.contentView = NSHostingView(rootView: OverlayRootView(viewModel: viewModel))
        return panel
    }
}
private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .statusBar
        hasShadow = false
        isOpaque = false
        backgroundColor = .clear
        isMovable = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }
}
struct OverlaySceneElement: Identifiable, Equatable {
    enum Kind: Equatable {
        case stroke(points: [CGPoint], width: CGFloat, colorHexRGBA: String, opacity: Double)
        case arrow(start: CGPoint, end: CGPoint, width: CGFloat, colorHexRGBA: String, opacity: Double)
        case rectangle(rect: CGRect, width: CGFloat, colorHexRGBA: String, opacity: Double)
        case ellipse(rect: CGRect, width: CGFloat, colorHexRGBA: String, opacity: Double)
        case text(text: String, center: CGPoint, fontSize: CGFloat, colorHexRGBA: String, opacity: Double)
    }
    let id: UUID
    var kind: Kind
    init(id: UUID = UUID(), kind: Kind) {
        self.id = id
        self.kind = kind
    }
    var colorHexRGBA: String {
        switch kind {
        case let .stroke(_, _, colorHexRGBA, _):
            return colorHexRGBA
        case let .arrow(_, _, _, colorHexRGBA, _):
            return colorHexRGBA
        case let .rectangle(_, _, colorHexRGBA, _):
            return colorHexRGBA
        case let .ellipse(_, _, colorHexRGBA, _):
            return colorHexRGBA
        case let .text(_, _, _, colorHexRGBA, _):
            return colorHexRGBA
        }
    }
    var opacity: Double {
        switch kind {
        case let .stroke(_, _, _, opacity):
            return opacity
        case let .arrow(_, _, _, _, opacity):
            return opacity
        case let .rectangle(_, _, _, opacity):
            return opacity
        case let .ellipse(_, _, _, opacity):
            return opacity
        case let .text(_, _, _, _, opacity):
            return opacity
        }
    }
    var lineWidth: CGFloat {
        switch kind {
        case let .stroke(_, width, _, _):
            return width
        case let .arrow(_, _, width, _, _):
            return width
        case let .rectangle(_, width, _, _):
            return width
        case let .ellipse(_, width, _, _):
            return width
        case .text:
            return 0
        }
    }
}
private struct OverlayTextItem: Identifiable, Equatable {
    let id: UUID
    let text: String
    let center: CGPoint
    let fontSize: CGFloat
    let colorHexRGBA: String
    let opacity: Double
}
private struct TextDraft: Equatable {
    var text: String
    var center: CGPoint
}
struct OverlaySceneModel {
    enum Command {
        case add(OverlaySceneElement)
        case remove(OverlaySceneElement)
        case clear([OverlaySceneElement])
    }
    private(set) var elements: [OverlaySceneElement] = []
    private(set) var undoStack: [Command] = []
    private(set) var redoStack: [Command] = []
    mutating func commit(_ element: OverlaySceneElement) {
        elements.append(element)
        undoStack.append(.add(element))
        redoStack.removeAll()
    }
    mutating func eraseTopmostElement(at point: CGPoint) -> Bool {
        guard let index = elements.lastIndex(where: { $0.hitTest(point) }) else {
            return false
        }
        let removed = elements.remove(at: index)
        undoStack.append(.remove(removed))
        redoStack.removeAll()
        return true
    }
    mutating func clearAll(allowUndo: Bool) {
        guard !elements.isEmpty else { return }
        let removed = elements
        elements.removeAll()
        if allowUndo {
            undoStack.append(.clear(removed))
            redoStack.removeAll()
        } else {
            undoStack.removeAll()
            redoStack.removeAll()
        }
    }
    mutating func undo() {
        guard let command = undoStack.popLast() else { return }
        applyUndo(command)
        redoStack.append(command)
    }
    mutating func redo() {
        guard let command = redoStack.popLast() else { return }
        applyRedo(command)
        undoStack.append(command)
    }
    private mutating func applyUndo(_ command: Command) {
        switch command {
        case let .add(element):
            elements.removeAll { $0.id == element.id }
        case let .remove(element):
            elements.append(element)
        case let .clear(removed):
            elements = removed
        }
    }
    private mutating func applyRedo(_ command: Command) {
        switch command {
        case let .add(element):
            elements.append(element)
        case let .remove(element):
            elements.removeAll { $0.id == element.id }
        case .clear:
            elements.removeAll()
        }
    }
}
@MainActor
private final class OverlayViewModel: ObservableObject {
    enum RadialItem: Identifiable, Equatable {
        case tool(ToolKind)
        case action(OverlayAction)
        var id: String {
            switch self {
            case let .tool(tool):
                return "tool.\(tool.rawValue)"
            case let .action(action):
                return "action.\(action.id)"
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
    @Published var selectedToolForOptions: ToolKind?
    @Published var radialCenter = CGPoint(x: 220, y: 220)
    @Published var shortcutLabelByCommand: [ShortcutCommandID: String] = [:]
    var commandHandler: (@MainActor (OverlayAction) -> Void)?
    var strokeDurationRecorder: ((Double) -> Void)?
    private var scene = OverlaySceneModel()
    private var drawingStartPoint: CGPoint?
    private var currentStrokePoints: [CGPoint] = []
    private var strokeStartTime: Date?
    private var radialCollapseTask: Task<Void, Never>?
    private let radialEdgeInset: CGFloat = 56
    var activeConfig: ToolConfig {
        toolState.configs[toolState.activeTool] ?? ToolConfig(colorHexRGBA: "#FF3B30FF", strokeWidth: 4, opacity: 1)
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
    var radialSecondaryItems: [RadialItem] {
        guard selectedToolForOptions != nil else {
            return []
        }
        return [
            .action(.cycleColors),
            .action(.increaseStroke),
            .action(.decreaseStroke)
        ]
    }
    func handleDragChanged(_ value: DragGesture.Value) {
        cancelRadialCollapse()
        switch toolState.activeTool {
        case .pen, .highlighter:
            handleStrokeDragChanged(value.location)
        case .arrow, .rectangle, .ellipse:
            handleShapeDragChanged(value)
        case .eraser:
            break
        case .text:
            break
        }
    }
    func handleDragEnded(_ value: DragGesture.Value) {
        switch toolState.activeTool {
        case .pen, .highlighter:
            handleStrokeDragEnded()
        case .arrow, .rectangle, .ellipse:
            handleShapeDragEnded(value)
        case .text:
            if value.translation.length <= 6 {
                beginTextEditing(at: value.location)
            }
        case .eraser:
            if value.translation.length <= 6 {
                _ = scene.eraseTopmostElement(at: value.location)
                syncSceneState()
            }
        }
        drawingStartPoint = nil
        previewElement = nil
    }
    func commitTextDraft() {
        guard let textDraft else { return }
        let trimmed = textDraft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.textDraft = nil
        guard !trimmed.isEmpty else { return }
        let element = OverlaySceneElement(
            kind: .text(
                text: trimmed,
                center: textDraft.center,
                fontSize: CGFloat(activeConfig.strokeWidth),
                colorHexRGBA: activeConfig.colorHexRGBA,
                opacity: activeConfig.opacity
            )
        )
        scene.commit(element)
        syncSceneState()
    }
    func undoLastChange() {
        scene.undo()
        textDraft = nil
        syncSceneState()
    }
    func redoLastChange() {
        scene.redo()
        textDraft = nil
        syncSceneState()
    }
    func clearAll(allowUndo: Bool) {
        scene.clearAll(allowUndo: allowUndo)
        textDraft = nil
        syncSceneState()
    }
    func activateRadialControl() {
        guard isRadialControlEnabled else { return }
        isRadialExpanded = true
        cancelRadialCollapse()
    }
    func collapseRadialControl() {
        isRadialExpanded = false
        selectedToolForOptions = nil
        cancelRadialCollapse()
    }
    func scheduleRadialCollapse() {
        guard isRadialExpanded else { return }
        cancelRadialCollapse()
        radialCollapseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.collapseRadialControl()
        }
    }
    func moveRadialControl(to location: CGPoint, in size: CGSize) {
        let minX: CGFloat = radialEdgeInset
        let minY: CGFloat = radialEdgeInset
        let maxX = max(minX, size.width - radialEdgeInset)
        let maxY = max(minY, size.height - radialEdgeInset)
        let clamped = CGPoint(
            x: min(max(location.x, minX), maxX),
            y: min(max(location.y, minY), maxY)
        )
        radialCenter = snapToNearestEdge(point: clamped, bounds: size)
    }
    func selectPrimaryItem(_ item: RadialItem) {
        activateRadialControl()
        switch item {
        case let .tool(tool):
            selectedToolForOptions = tool
            commandHandler?(.selectTool(tool))
        case let .action(action):
            selectedToolForOptions = nil
            commandHandler?(action)
        }
    }
    func selectSecondaryItem(_ item: RadialItem) {
        activateRadialControl()
        if case let .action(action) = item {
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
    private func beginTextEditing(at point: CGPoint) {
        commitTextDraft()
        textDraft = TextDraft(text: "", center: point)
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
                opacity: activeConfig.opacity
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
                opacity: activeConfig.opacity
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
    private func handleShapeDragChanged(_ value: DragGesture.Value) {
        if drawingStartPoint == nil {
            drawingStartPoint = value.startLocation
        }
        let start = drawingStartPoint ?? value.startLocation
        let end = value.location
        switch toolState.activeTool {
        case .arrow:
            previewElement = OverlaySceneElement(
                kind: .arrow(
                    start: start,
                    end: end,
                    width: CGFloat(activeConfig.strokeWidth),
                    colorHexRGBA: activeConfig.colorHexRGBA,
                    opacity: activeConfig.opacity
                )
            )
        case .rectangle:
            previewElement = OverlaySceneElement(
                kind: .rectangle(
                    rect: CGRect.normalized(from: start, to: end),
                    width: CGFloat(activeConfig.strokeWidth),
                    colorHexRGBA: activeConfig.colorHexRGBA,
                    opacity: activeConfig.opacity
                )
            )
        case .ellipse:
            previewElement = OverlaySceneElement(
                kind: .ellipse(
                    rect: CGRect.normalized(from: start, to: end),
                    width: CGFloat(activeConfig.strokeWidth),
                    colorHexRGBA: activeConfig.colorHexRGBA,
                    opacity: activeConfig.opacity
                )
            )
        case .pen, .highlighter, .text, .eraser:
            break
        }
    }
    private func handleShapeDragEnded(_ value: DragGesture.Value) {
        if value.translation.length < 2 {
            return
        }
        guard let previewElement else { return }
        scene.commit(previewElement)
        syncSceneState()
    }
    private func syncSceneState() {
        sceneElements = scene.elements
        textItems = scene.elements.compactMap { element in
            guard case let .text(text, center, fontSize, colorHexRGBA, opacity) = element.kind else {
                return nil
            }
            return OverlayTextItem(
                id: element.id,
                text: text,
                center: center,
                fontSize: fontSize,
                colorHexRGBA: colorHexRGBA,
                opacity: opacity
            )
        }
    }
    private func cancelRadialCollapse() {
        radialCollapseTask?.cancel()
        radialCollapseTask = nil
    }
    private func snapToNearestEdge(point: CGPoint, bounds: CGSize) -> CGPoint {
        let leftDistance = point.x
        let rightDistance = bounds.width - point.x
        if leftDistance < rightDistance {
            return CGPoint(x: radialEdgeInset, y: point.y)
        }
        return CGPoint(x: max(radialEdgeInset, bounds.width - radialEdgeInset), y: point.y)
    }
}
private struct OverlayRootView: View {
    @ObservedObject var viewModel: OverlayViewModel
    @FocusState private var isTextDraftFocused: Bool
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                viewModel.handleDragChanged(value)
                            }
                            .onEnded { value in
                                viewModel.handleDragEnded(value)
                            }
                    )
                Canvas { context, _ in
                    for element in viewModel.sceneElements {
                        render(element: element, in: &context)
                    }
                    if let previewElement = viewModel.previewElement {
                        render(element: previewElement, in: &context)
                    }
                }
                ForEach(viewModel.textItems) { item in
                    Text(item.text)
                        .font(.system(size: item.fontSize, weight: .semibold))
                        .foregroundStyle(Color(hexRGBA: item.colorHexRGBA).opacity(item.opacity))
                        .position(x: item.center.x, y: item.center.y)
                        .allowsHitTesting(false)
                }
                if let textDraft = viewModel.textDraft {
                    TextField("Type text", text: Binding(
                        get: { viewModel.textDraft?.text ?? "" },
                        set: { viewModel.textDraft?.text = $0 }
                    ))
                    .font(.system(size: CGFloat(viewModel.activeConfig.strokeWidth), weight: .semibold))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .foregroundStyle(Color(hexRGBA: viewModel.activeConfig.colorHexRGBA).opacity(viewModel.activeConfig.opacity))
                    .position(x: textDraft.center.x, y: textDraft.center.y)
                    .focused($isTextDraftFocused)
                    .onSubmit {
                        viewModel.commitTextDraft()
                    }
                    .onAppear {
                        isTextDraftFocused = true
                    }
                }
                HUDView(
                    text: viewModel.hudText,
                    color: viewModel.hudColor,
                    tooltip: viewModel.hudTooltip
                )
                .padding(20)
                if viewModel.isRadialControlEnabled {
                    RadialControlView(viewModel: viewModel, availableSize: proxy.size)
                }
            }
        }
        .ignoresSafeArea()
        .opacity(viewModel.isOverlayVisible ? 1 : 0)
        .allowsHitTesting(viewModel.isOverlayVisible)
        .animation(.easeInOut(duration: 0.12), value: viewModel.isOverlayVisible)
    }
    private func render(element: OverlaySceneElement, in context: inout GraphicsContext) {
        switch element.kind {
        case let .stroke(points, width, colorHexRGBA, opacity):
            let path = makeStrokePath(points: points)
            context.stroke(
                path,
                with: .color(Color(hexRGBA: colorHexRGBA).opacity(opacity)),
                style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
            )
        case let .arrow(start, end, width, colorHexRGBA, opacity):
            let path = makeArrowPath(start: start, end: end)
            context.stroke(
                path,
                with: .color(Color(hexRGBA: colorHexRGBA).opacity(opacity)),
                style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
            )
        case let .rectangle(rect, width, colorHexRGBA, opacity):
            context.stroke(
                Path(rect),
                with: .color(Color(hexRGBA: colorHexRGBA).opacity(opacity)),
                style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
            )
        case let .ellipse(rect, width, colorHexRGBA, opacity):
            context.stroke(
                Path(ellipseIn: rect),
                with: .color(Color(hexRGBA: colorHexRGBA).opacity(opacity)),
                style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
            )
        case .text:
            break
        }
    }
    private func makeStrokePath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let firstPoint = points.first else {
            return path
        }
        path.move(to: firstPoint)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }
    private func makeArrowPath(start: CGPoint, end: CGPoint) -> Path {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowLength: CGFloat = 18
        let arrowAngle: CGFloat = .pi / 7
        let leftPoint = CGPoint(
            x: end.x - arrowLength * cos(angle - arrowAngle),
            y: end.y - arrowLength * sin(angle - arrowAngle)
        )
        let rightPoint = CGPoint(
            x: end.x - arrowLength * cos(angle + arrowAngle),
            y: end.y - arrowLength * sin(angle + arrowAngle)
        )
        path.move(to: end)
        path.addLine(to: leftPoint)
        path.move(to: end)
        path.addLine(to: rightPoint)
        return path
    }
}
private struct HUDView: View {
    let text: String
    let color: Color
    let tooltip: String
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.65), in: Capsule())
        .help(tooltip)
    }
}
private struct RadialControlView: View {
    @ObservedObject var viewModel: OverlayViewModel
    let availableSize: CGSize
    @State private var dragStartCenter: CGPoint?
    private let centerSize: CGFloat = 44
    private let primaryRadius: CGFloat = 88
    private let secondaryRadius: CGFloat = 132
    var body: some View {
        ZStack {
            if viewModel.isRadialExpanded {
                ringButtons(
                    items: viewModel.radialPrimaryItems,
                    radius: primaryRadius,
                    action: viewModel.selectPrimaryItem
                )
            }
            if viewModel.isRadialExpanded, !viewModel.radialSecondaryItems.isEmpty {
                ringButtons(
                    items: viewModel.radialSecondaryItems,
                    radius: secondaryRadius,
                    action: viewModel.selectSecondaryItem
                )
            }
            Button {
                if viewModel.isRadialExpanded {
                    viewModel.collapseRadialControl()
                } else {
                    viewModel.activateRadialControl()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(.black.opacity(0.75))
                    Image(systemName: viewModel.isRadialExpanded ? "xmark" : "circle.grid.2x2.fill")
                        .foregroundStyle(.white)
                }
                .frame(width: centerSize, height: centerSize)
            }
            .buttonStyle(.plain)
            .help("Radial Control")
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        viewModel.activateRadialControl()
                        if dragStartCenter == nil {
                            dragStartCenter = viewModel.radialCenter
                        }
                        let startCenter = dragStartCenter ?? viewModel.radialCenter
                        let nextPoint = CGPoint(
                            x: startCenter.x + value.translation.width,
                            y: startCenter.y + value.translation.height
                        )
                        viewModel.moveRadialControl(to: nextPoint, in: availableSize)
                    }
                    .onEnded { _ in
                        dragStartCenter = nil
                        viewModel.scheduleRadialCollapse()
                    }
            )
        }
        .position(viewModel.radialCenter)
        .onHover { isHovering in
            if isHovering {
                viewModel.activateRadialControl()
            } else {
                viewModel.scheduleRadialCollapse()
            }
        }
    }
    private func ringButtons(
        items: [OverlayViewModel.RadialItem],
        radius: CGFloat,
        action: @escaping (OverlayViewModel.RadialItem) -> Void
    ) -> some View {
        ZStack {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let angle = Double(index) / Double(max(items.count, 1)) * 2 * Double.pi
                Button {
                    action(item)
                } label: {
                    Image(systemName: item.symbolName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.black.opacity(0.8), in: Circle())
                }
                .buttonStyle(.plain)
                .help(viewModel.tooltip(for: item))
                .offset(
                    x: CGFloat(cos(angle)) * radius,
                    y: CGFloat(sin(angle)) * radius
                )
            }
        }
    }
}
private extension ToolKind {
    var shortcutCommandID: ShortcutCommandID {
        switch self {
        case .pen: return .selectPen
        case .highlighter: return .selectHighlighter
        case .arrow: return .selectArrow
        case .rectangle: return .selectRectangle
        case .ellipse: return .selectEllipse
        case .text: return .selectText
        case .eraser: return .selectEraser
        }
    }
}
private extension OverlayAction {
    var shortcutCommandID: ShortcutCommandID {
        switch self {
        case let .selectTool(tool):
            return tool.shortcutCommandID
        case .undo:
            return .undo
        case .redo:
            return .redo
        case .clearAll:
            return .clearAll
        case .cycleColors:
            return .cycleColors
        case .increaseStroke:
            return .increaseStroke
        case .decreaseStroke:
            return .decreaseStroke
        }
    }
    var id: String {
        switch self {
        case let .selectTool(tool):
            return "selectTool.\(tool.rawValue)"
        case .undo:
            return "undo"
        case .redo:
            return "redo"
        case .clearAll:
            return "clearAll"
        case .cycleColors:
            return "cycleColors"
        case .increaseStroke:
            return "increaseStroke"
        case .decreaseStroke:
            return "decreaseStroke"
        }
    }
    var label: String {
        switch self {
        case let .selectTool(tool):
            return tool.rawValue.capitalized
        case .undo:
            return "Undo"
        case .redo:
            return "Redo"
        case .clearAll:
            return "Clear All"
        case .cycleColors:
            return "Cycle Colors"
        case .increaseStroke:
            return "Increase Stroke"
        case .decreaseStroke:
            return "Decrease Stroke"
        }
    }
}
private extension OverlayViewModel.RadialItem {
    var symbolName: String {
        switch self {
        case let .tool(tool):
            switch tool {
            case .pen: return "pencil.tip"
            case .highlighter: return "highlighter"
            case .arrow: return "arrow.up.right"
            case .rectangle: return "rectangle"
            case .ellipse: return "circle"
            case .text: return "textformat"
            case .eraser: return "eraser"
            }
        case let .action(action):
            switch action {
            case .undo: return "arrow.uturn.backward"
            case .redo: return "arrow.uturn.forward"
            case .clearAll: return "trash"
            case .cycleColors: return "paintpalette"
            case .increaseStroke: return "plus"
            case .decreaseStroke: return "minus"
            case .selectTool:
                assertionFailure("selectTool should be represented as RadialItem.tool, not RadialItem.action")
                return "pencil"
            }
        }
    }
}
private extension ShortcutBinding {
    var displayText: String {
        var segments: [String] = []
        if modifiers.contains(.control) { segments.append("Ctrl") }
        if modifiers.contains(.option) { segments.append("Opt") }
        if modifiers.contains(.shift) { segments.append("Shift") }
        if modifiers.contains(.command) { segments.append("Cmd") }
        segments.append(key.displayText)
        return segments.joined(separator: "+")
    }
}
private extension ShortcutKey {
    var displayText: String {
        switch self {
        case .a: return "A"
        case .r: return "R"
        case .p: return "P"
        case .one: return "1"
        case .two: return "2"
        case .three: return "3"
        case .four: return "4"
        case .five: return "5"
        case .six: return "6"
        case .e: return "E"
        case .z: return "Z"
        case .c: return "C"
        case .leftBracket: return "["
        case .rightBracket: return "]"
        case .space: return "Space"
        case .backspace: return "Backspace"
        }
    }
}
private extension OverlaySceneElement {
    func hitTest(_ point: CGPoint) -> Bool {
        switch kind {
        case let .stroke(points, width, _, _):
            return point.distanceToPolyline(points) <= max(width * 0.5, 8)
        case let .arrow(start, end, width, _, _):
            return point.distanceToSegment(from: start, to: end) <= max(width * 0.6, 10)
        case let .rectangle(rect, width, _, _):
            return rect.insetBy(dx: -max(width, 10), dy: -max(width, 10)).contains(point)
        case let .ellipse(rect, width, _, _):
            let expanded = rect.insetBy(dx: -max(width, 10), dy: -max(width, 10))
            return expanded.contains(point)
        case let .text(text, center, fontSize, _, _):
            let bounds = CGRect(textCenter: center, text: text, fontSize: fontSize)
            return bounds.contains(point)
        }
    }
}
private extension CGSize {
    var length: CGFloat {
        sqrt((width * width) + (height * height))
    }
}
private extension CGPoint {
    func distanceToPolyline(_ points: [CGPoint]) -> CGFloat {
        guard points.count > 1 else {
            return points.first.map { hypot(x - $0.x, y - $0.y) } ?? .greatestFiniteMagnitude
        }
        var minimumDistance = CGFloat.greatestFiniteMagnitude
        for index in 0..<(points.count - 1) {
            let distance = distanceToSegment(from: points[index], to: points[index + 1])
            minimumDistance = min(minimumDistance, distance)
        }
        return minimumDistance
    }
    func distanceToSegment(from start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = (dx * dx) + (dy * dy)
        if lengthSquared == 0 {
            return hypot(x - start.x, y - start.y)
        }
        let t = max(0, min(1, ((x - start.x) * dx + (y - start.y) * dy) / lengthSquared))
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(x - projection.x, y - projection.y)
    }
}
private extension CGRect {
    static func normalized(from first: CGPoint, to second: CGPoint) -> CGRect {
        CGRect(
            x: min(first.x, second.x),
            y: min(first.y, second.y),
            width: abs(first.x - second.x),
            height: abs(first.y - second.y)
        )
    }
    init(textCenter: CGPoint, text: String, fontSize: CGFloat) {
        let estimatedWidth = max(44, CGFloat(text.count) * fontSize * 0.62)
        let estimatedHeight = max(24, fontSize * 1.5)
        self.init(
            x: textCenter.x - (estimatedWidth * 0.5),
            y: textCenter.y - (estimatedHeight * 0.5),
            width: estimatedWidth,
            height: estimatedHeight
        )
    }
}
private extension Color {
    init(hexRGBA: String) {
        let value = hexRGBA.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: value).scanHexInt64(&int)
        let r: UInt64
        let g: UInt64
        let b: UInt64
        let a: UInt64
        switch value.count {
        case 8:
            (r, g, b, a) = (
                (int >> 24) & 0xff,
                (int >> 16) & 0xff,
                (int >> 8) & 0xff,
                int & 0xff
            )
        case 6:
            (r, g, b, a) = (
                (int >> 16) & 0xff,
                (int >> 8) & 0xff,
                int & 0xff,
                0xff
            )
        default:
            (r, g, b, a) = (255, 59, 48, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
