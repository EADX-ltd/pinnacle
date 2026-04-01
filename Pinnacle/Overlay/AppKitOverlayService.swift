import AppKit
import Combine
import Foundation
import SwiftUI
import os
@MainActor
final class AppKitOverlayService: OverlayService {
    private let logger = Logger(subsystem: "Pinnacle", category: "Overlay")
    private let viewModel = OverlayViewModel()
    private var overlayPanelByDisplayID: [CGDirectDisplayID: OverlayPanel] = [:]
    private var activeDisplayID: CGDirectDisplayID?
    private var screenObserver: NSObjectProtocol?
    private var drawEventMonitor: Any?
    private var dragStartGlobalPoint: CGPoint?
    init() {
        viewModel.strokeDurationRecorder = { [logger] durationMs in
            logger.log("Pen stroke duration baseline: \(durationMs, format: .fixed(precision: 2), privacy: .public)ms")
        }
        viewModel.onTextEditingActive = { [weak self] isEditing in
            guard let self else { return }
            if isEditing {
                if let id = self.activeDisplayID, let panel = self.overlayPanelByDisplayID[id] {
                    NSApp.activate(ignoringOtherApps: true)
                    panel.makeKey()
                }
            } else {
                for panel in self.overlayPanelByDisplayID.values where NSApp.keyWindow === panel {
                    panel.resignKey()
                    break
                }
            }
        }
    }
    func startOverlay() {
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.synchronizeOverlayPanels()
                    if self.viewModel.isOverlayVisible {
                        self.orderActivePanelFront()
                    }
                }
            }
        }
        synchronizeOverlayPanels()
        guard !overlayPanelByDisplayID.isEmpty else {
            logger.error("No screen available - overlay panels cannot be created")
            return
        }
        activeDisplayID = mouseDisplayID()
        viewModel.isOverlayVisible = true
        orderActivePanelFront()
        installMouseEventMonitor()
        logger.log("Overlay started on display id=\(self.activeDisplayID ?? 0, privacy: .public)")
    }
    func stopOverlay() {
        viewModel.isOverlayVisible = false
        viewModel.collapseRadialControl()
        removeMouseEventMonitor()
        for panel in overlayPanelByDisplayID.values {
            panel.orderOut(nil)
        }
        activeDisplayID = nil
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
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
    private func orderActivePanelFront() {
        let targetID = activeDisplayID
            ?? NSScreen.main?.displayDescriptor?.id
            ?? overlayPanelByDisplayID.keys.first
        for (id, panel) in overlayPanelByDisplayID {
            if id == targetID {
                panel.orderFrontRegardless()
            } else {
                panel.orderOut(nil)
            }
        }
    }

    private func mouseDisplayID() -> CGDirectDisplayID? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(location) }?.displayDescriptor?.id
    }
    private func synchronizeOverlayPanels() {
        let descriptors = NSScreen.screens.compactMap(\.displayDescriptor)
        let activeIDs = Set(descriptors.map(\.id))
        let staleIDs = Set(overlayPanelByDisplayID.keys).subtracting(activeIDs)
        for staleID in staleIDs {
            overlayPanelByDisplayID[staleID]?.close()
            overlayPanelByDisplayID[staleID] = nil
            logger.log("Removed overlay panel for detached display id=\(staleID, privacy: .public)")
        }
        for descriptor in descriptors {
            if let panel = overlayPanelByDisplayID[descriptor.id] {
                if panel.frame != descriptor.frame {
                    panel.setFrame(descriptor.frame, display: true)
                }
                continue
            }
            guard let panel = makeOverlayPanel(for: descriptor) else {
                logger.error("Failed to create overlay panel for display id=\(descriptor.id, privacy: .public)")
                continue
            }
            overlayPanelByDisplayID[descriptor.id] = panel
            logger.log("Created overlay panel for display id=\(descriptor.id, privacy: .public)")
        }
    }
    private func makeOverlayPanel(for descriptor: DisplayDescriptor) -> OverlayPanel? {
        let panel = OverlayPanel(contentRect: descriptor.frame)
        panel.contentView = NSHostingView(
            rootView: OverlayRootView(
                viewModel: viewModel,
                coordinateTransformer: DisplayCoordinateTransformer(displayFrame: descriptor.frame)
            )
        )
        return panel
    }

    private func installMouseEventMonitor() {
        guard drawEventMonitor == nil else { return }
        drawEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.handleOverlayMouseEvent(event)
            return event
        }
    }

    private func removeMouseEventMonitor() {
        guard let monitor = drawEventMonitor else { return }
        NSEvent.removeMonitor(monitor)
        drawEventMonitor = nil
        dragStartGlobalPoint = nil
    }

    private func handleOverlayMouseEvent(_ event: NSEvent) {
        guard viewModel.isOverlayVisible else { return }
        guard let panel = event.window as? OverlayPanel,
              let (displayID, _) = overlayPanelByDisplayID.first(where: { $0.value === panel }),
              let descriptor = NSScreen.screens.compactMap(\.displayDescriptor).first(where: { $0.id == displayID })
        else { return }

        // Convert AppKit window coords (Y-up) → SwiftUI panel coords (Y-down)
        let winPt = event.locationInWindow
        let localPt = CGPoint(x: winPt.x, y: descriptor.frame.height - winPt.y)

        // Don't start drawing inside the radial control area
        let radialRadius: CGFloat = viewModel.isRadialExpanded ? 160 : 28
        if hypot(localPt.x - viewModel.radialCenter.x, localPt.y - viewModel.radialCenter.y) < radialRadius {
            return
        }

        let transformer = DisplayCoordinateTransformer(displayFrame: descriptor.frame)
        let globalPt = transformer.localPointToGlobal(localPt)

        switch event.type {
        case .leftMouseDown:
            dragStartGlobalPoint = globalPt
            viewModel.handleDragChanged(startLocation: globalPt, location: globalPt)
        case .leftMouseDragged:
            guard let startPt = dragStartGlobalPoint else { return }
            viewModel.handleDragChanged(startLocation: startPt, location: globalPt)
        case .leftMouseUp:
            let startPt = dragStartGlobalPoint ?? globalPt
            let translation = CGSize(width: globalPt.x - startPt.x, height: globalPt.y - startPt.y)
            viewModel.handleDragEnded(startLocation: startPt, location: globalPt, translation: translation)
            dragStartGlobalPoint = nil
        default:
            break
        }
    }
}
private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
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
struct DisplayDescriptor: Equatable {
    let id: CGDirectDisplayID
    let frame: CGRect
    let scaleFactor: CGFloat
}
struct DisplayCoordinateTransformer: Equatable {
    let displayFrame: CGRect
    func localPointToGlobal(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x + displayFrame.minX, y: point.y + displayFrame.minY)
    }
    func globalPointToLocal(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - displayFrame.minX, y: point.y - displayFrame.minY)
    }
    func localRectToGlobal(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x + displayFrame.minX,
            y: rect.origin.y + displayFrame.minY,
            width: rect.width,
            height: rect.height
        )
    }
    func globalRectToLocal(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x - displayFrame.minX,
            y: rect.origin.y - displayFrame.minY,
            width: rect.width,
            height: rect.height
        )
    }
}
private extension NSScreen {
    var displayDescriptor: DisplayDescriptor? {
        guard let displayNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return DisplayDescriptor(
            id: CGDirectDisplayID(displayNumber.uint32Value),
            frame: frame,
            scaleFactor: backingScaleFactor
        )
    }
}
struct OverlaySceneElement: Identifiable, Equatable {
    enum Kind: Equatable {
        case stroke(points: [CGPoint], width: CGFloat, colorHexRGBA: String, opacity: Double, lineStyle: LineStyle)
        case arrow(start: CGPoint, end: CGPoint, width: CGFloat, colorHexRGBA: String, opacity: Double, lineStyle: LineStyle, arrowStyle: ArrowStyle)
        case rectangle(rect: CGRect, width: CGFloat, colorHexRGBA: String, opacity: Double, lineStyle: LineStyle)
        case ellipse(rect: CGRect, width: CGFloat, colorHexRGBA: String, opacity: Double, lineStyle: LineStyle)
        case text(text: String, center: CGPoint, fontSize: CGFloat, colorHexRGBA: String, opacity: Double, fontDesign: TextFontDesign)
    }
    let id: UUID
    var kind: Kind
    init(id: UUID = UUID(), kind: Kind) {
        self.id = id
        self.kind = kind
    }
    var colorHexRGBA: String {
        switch kind {
        case let .stroke(_, _, colorHexRGBA, _, _):
            return colorHexRGBA
        case let .arrow(_, _, _, colorHexRGBA, _, _, _):
            return colorHexRGBA
        case let .rectangle(_, _, colorHexRGBA, _, _):
            return colorHexRGBA
        case let .ellipse(_, _, colorHexRGBA, _, _):
            return colorHexRGBA
        case let .text(_, _, _, colorHexRGBA, _, _):
            return colorHexRGBA
        }
    }
    var opacity: Double {
        switch kind {
        case let .stroke(_, _, _, opacity, _):
            return opacity
        case let .arrow(_, _, _, _, opacity, _, _):
            return opacity
        case let .rectangle(_, _, _, opacity, _):
            return opacity
        case let .ellipse(_, _, _, opacity, _):
            return opacity
        case let .text(_, _, _, _, opacity, _):
            return opacity
        }
    }
    var lineWidth: CGFloat {
        switch kind {
        case let .stroke(_, width, _, _, _):
            return width
        case let .arrow(_, _, width, _, _, _, _):
            return width
        case let .rectangle(_, width, _, _, _):
            return width
        case let .ellipse(_, width, _, _, _):
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
    let fontDesign: TextFontDesign
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
    @Published var isOptionsOpen = false
    @Published var pendingConfig: ToolConfig = ToolState.default.configs[.pen]!
    @Published var pendingExtendedOptions: ToolExtendedOptions = .default
    @Published var radialCenter = CGPoint(x: 220, y: 220)
    @Published var shortcutLabelByCommand: [ShortcutCommandID: String] = [:]
    var commandHandler: (@MainActor (OverlayAction) -> Void)?
    var strokeDurationRecorder: ((Double) -> Void)?
    var onTextEditingActive: ((Bool) -> Void)?
    private var scene = OverlaySceneModel()
    private var drawingStartPoint: CGPoint?
    private var currentStrokePoints: [CGPoint] = []
    private var strokeStartTime: Date?
    private var radialCollapseTask: Task<Void, Never>?
    private let radialEdgeInset: CGFloat = 56
    var activeConfig: ToolConfig {
        toolState.configs[toolState.activeTool] ?? ToolConfig(colorHexRGBA: "#FF3B30FF", strokeWidth: 4, opacity: 1)
    }
    var activeExtendedOptions: ToolExtendedOptions {
        toolState.extendedOptions[toolState.activeTool] ?? .default
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
        cancelRadialCollapse()
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
        self.textDraft = nil
        onTextEditingActive?(false)
        guard !trimmed.isEmpty else { return }
        let element = OverlaySceneElement(
            kind: .text(
                text: trimmed,
                center: textDraft.center,
                fontSize: CGFloat(activeConfig.strokeWidth),
                colorHexRGBA: activeConfig.colorHexRGBA,
                opacity: activeConfig.opacity,
                fontDesign: activeExtendedOptions.textFontDesign
            )
        )
        scene.commit(element)
        syncSceneState()
    }
    func undoLastChange() {
        scene.undo()
        if textDraft != nil { textDraft = nil; onTextEditingActive?(false) }
        syncSceneState()
    }
    func redoLastChange() {
        scene.redo()
        textDraft = nil
        syncSceneState()
    }
    func clearAll(allowUndo: Bool) {
        scene.clearAll(allowUndo: allowUndo)
        if textDraft != nil { textDraft = nil; onTextEditingActive?(false) }
        syncSceneState()
    }
    func activateRadialControl() {
        guard isRadialControlEnabled else { return }
        if !isRadialExpanded { isRadialExpanded = true }
        cancelRadialCollapse()
    }
    func collapseRadialControl() {
        isRadialExpanded = false
        selectedToolForOptions = nil
        isOptionsOpen = false
        cancelRadialCollapse()
    }
    func scheduleRadialCollapse() {
        guard isRadialExpanded, !isOptionsOpen else { return }
        cancelRadialCollapse()
        radialCollapseTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
            self?.collapseRadialControl()
        }
    }
    func openOptions() {
        guard isRadialExpanded,
              let tool = selectedToolForOptions,
              tool.hasConfigurableOptions else { return }
        pendingConfig = toolState.configs[tool] ?? ToolConfig(colorHexRGBA: "#FF3B30FF", strokeWidth: 4, opacity: 1)
        pendingExtendedOptions = toolState.extendedOptions[tool] ?? .default
        isOptionsOpen = true
        cancelRadialCollapse()
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
        activateRadialControl()
        switch item {
        case let .tool(tool):
            // Close options if switching away from the currently configured tool
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
    private func beginTextEditing(at point: CGPoint) {
        commitTextDraft()
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
        if translation.length < 2 {
            return
        }
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
    private func cancelRadialCollapse() {
        radialCollapseTask?.cancel()
        radialCollapseTask = nil
    }
}
private struct OverlayTextField: NSViewRepresentable {
    @Binding var text: String
    let font: NSFont
    let color: NSColor
    let onCommit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isEditable = true
        field.isSelectable = true
        field.font = font
        field.textColor = color
        field.alignment = .center
        field.delegate = context.coordinator
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        nsView.font = font
        nsView.textColor = color
        if nsView.stringValue != text { nsView.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: OverlayTextField
        init(_ parent: OverlayTextField) { self.parent = parent }
        func controlTextDidChange(_ n: Notification) {
            guard let f = n.object as? NSTextField else { return }
            parent.text = f.stringValue
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            if sel == #selector(NSResponder.insertNewline(_:)) { parent.onCommit(); return true }
            return false
        }
    }
}

private struct OverlayRootView: View {
    @ObservedObject var viewModel: OverlayViewModel
    let coordinateTransformer: DisplayCoordinateTransformer
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.clear
                Canvas { context, _ in
                    for element in viewModel.sceneElements {
                        guard let localElement = localElement(for: element) else {
                            continue
                        }
                        render(element: localElement, in: &context)
                    }
                    if let previewElement = viewModel.previewElement {
                        if let localPreviewElement = localElement(for: previewElement) {
                            render(element: localPreviewElement, in: &context)
                        }
                    }
                }
                ForEach(viewModel.textItems) { item in
                    if coordinateTransformer.displayFrame.contains(item.center) {
                        let localCenter = coordinateTransformer.globalPointToLocal(item.center)
                        Text(item.text)
                            .font(.system(size: item.fontSize, weight: .semibold, design: item.fontDesign.fontDesign))
                            .foregroundStyle(Color(hexRGBA: item.colorHexRGBA).opacity(item.opacity))
                            .position(x: localCenter.x, y: localCenter.y)
                            .allowsHitTesting(false)
                    }
                }
                if let textDraft = viewModel.textDraft, coordinateTransformer.displayFrame.contains(textDraft.center) {
                    let fontSize = CGFloat(viewModel.activeConfig.strokeWidth)
                    let nsColor = NSColor(Color(hexRGBA: viewModel.activeConfig.colorHexRGBA).opacity(viewModel.activeConfig.opacity))
                    OverlayTextField(
                        text: Binding(
                            get: { viewModel.textDraft?.text ?? "" },
                            set: { viewModel.textDraft?.text = $0 }
                        ),
                        font: .systemFont(ofSize: fontSize, weight: .semibold),
                        color: nsColor,
                        onCommit: { viewModel.commitTextDraft() }
                    )
                    .frame(width: 300, height: fontSize * 1.5)
                    .position(
                        x: coordinateTransformer.globalPointToLocal(textDraft.center).x,
                        y: coordinateTransformer.globalPointToLocal(textDraft.center).y
                    )
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
            .coordinateSpace(name: "overlay")
        }
        .ignoresSafeArea()
        .opacity(viewModel.isOverlayVisible ? 1 : 0)
        .allowsHitTesting(viewModel.isOverlayVisible)
        .animation(.easeInOut(duration: 0.12), value: viewModel.isOverlayVisible)
    }
    private func localElement(for element: OverlaySceneElement) -> OverlaySceneElement? {
        switch element.kind {
        case let .stroke(points, width, colorHexRGBA, opacity, lineStyle):
            let globalBounds = points.boundingRect
            guard coordinateTransformer.displayFrame.intersects(globalBounds) else { return nil }
            return OverlaySceneElement(
                id: element.id,
                kind: .stroke(
                    points: points.map { coordinateTransformer.globalPointToLocal($0) },
                    width: width,
                    colorHexRGBA: colorHexRGBA,
                    opacity: opacity,
                    lineStyle: lineStyle
                )
            )
        case let .arrow(start, end, width, colorHexRGBA, opacity, lineStyle, arrowStyle):
            let boundsPadding = max(width, OverlayGeometry.arrowHeadLength)
            let globalBounds = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(start.x - end.x),
                height: abs(start.y - end.y)
            ).insetBy(dx: -boundsPadding, dy: -boundsPadding)
            guard coordinateTransformer.displayFrame.intersects(globalBounds) else { return nil }
            return OverlaySceneElement(
                id: element.id,
                kind: .arrow(
                    start: coordinateTransformer.globalPointToLocal(start),
                    end: coordinateTransformer.globalPointToLocal(end),
                    width: width,
                    colorHexRGBA: colorHexRGBA,
                    opacity: opacity,
                    lineStyle: lineStyle,
                    arrowStyle: arrowStyle
                )
            )
        case let .rectangle(rect, width, colorHexRGBA, opacity, lineStyle):
            guard coordinateTransformer.displayFrame.intersects(rect) else { return nil }
            return OverlaySceneElement(
                id: element.id,
                kind: .rectangle(
                    rect: coordinateTransformer.globalRectToLocal(rect),
                    width: width,
                    colorHexRGBA: colorHexRGBA,
                    opacity: opacity,
                    lineStyle: lineStyle
                )
            )
        case let .ellipse(rect, width, colorHexRGBA, opacity, lineStyle):
            guard coordinateTransformer.displayFrame.intersects(rect) else { return nil }
            return OverlaySceneElement(
                id: element.id,
                kind: .ellipse(
                    rect: coordinateTransformer.globalRectToLocal(rect),
                    width: width,
                    colorHexRGBA: colorHexRGBA,
                    opacity: opacity,
                    lineStyle: lineStyle
                )
            )
        case let .text(text, center, fontSize, colorHexRGBA, opacity, fontDesign):
            guard coordinateTransformer.displayFrame.contains(center) else { return nil }
            return OverlaySceneElement(
                id: element.id,
                kind: .text(
                    text: text,
                    center: coordinateTransformer.globalPointToLocal(center),
                    fontSize: fontSize,
                    colorHexRGBA: colorHexRGBA,
                    opacity: opacity,
                    fontDesign: fontDesign
                )
            )
        }
    }
    private func render(element: OverlaySceneElement, in context: inout GraphicsContext) {
        switch element.kind {
        case let .stroke(points, width, colorHexRGBA, opacity, lineStyle):
            let path = makeStrokePath(points: points)
            context.stroke(
                path,
                with: .color(Color(hexRGBA: colorHexRGBA).opacity(opacity)),
                style: makeStrokeStyle(width: width, lineStyle: lineStyle, cap: .round, join: .round)
            )
        case let .arrow(start, end, width, colorHexRGBA, opacity, lineStyle, arrowStyle):
            let path = makeArrowPath(start: start, end: end, arrowStyle: arrowStyle)
            context.stroke(
                path,
                with: .color(Color(hexRGBA: colorHexRGBA).opacity(opacity)),
                style: makeStrokeStyle(width: width, lineStyle: lineStyle, cap: .round, join: .round)
            )
        case let .rectangle(rect, width, colorHexRGBA, opacity, lineStyle):
            context.stroke(
                Path(rect),
                with: .color(Color(hexRGBA: colorHexRGBA).opacity(opacity)),
                style: makeStrokeStyle(width: width, lineStyle: lineStyle, cap: .round, join: .round)
            )
        case let .ellipse(rect, width, colorHexRGBA, opacity, lineStyle):
            context.stroke(
                Path(ellipseIn: rect),
                with: .color(Color(hexRGBA: colorHexRGBA).opacity(opacity)),
                style: makeStrokeStyle(width: width, lineStyle: lineStyle, cap: .round, join: .round)
            )
        case .text:
            break
        }
    }
    private func makeStrokeStyle(width: CGFloat, lineStyle: LineStyle, cap: CGLineCap = .round, join: CGLineJoin = .round) -> StrokeStyle {
        switch lineStyle {
        case .solid:
            return StrokeStyle(lineWidth: width, lineCap: cap, lineJoin: join)
        case .dotted:
            return StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: join, dash: [width * 0.1, width * 2.5])
        case .dashed:
            return StrokeStyle(lineWidth: width, lineCap: .butt, lineJoin: join, dash: [width * 3, width * 1.5])
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
    private func makeArrowPath(start: CGPoint, end: CGPoint, arrowStyle: ArrowStyle) -> Path {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        let forwardAngle = atan2(end.y - start.y, end.x - start.x)
        let arrowLength = OverlayGeometry.arrowHeadLength
        let arrowAngle: CGFloat = .pi / 7
        // Arrowhead at end
        path.move(to: end)
        path.addLine(to: CGPoint(
            x: end.x - arrowLength * cos(forwardAngle - arrowAngle),
            y: end.y - arrowLength * sin(forwardAngle - arrowAngle)
        ))
        path.move(to: end)
        path.addLine(to: CGPoint(
            x: end.x - arrowLength * cos(forwardAngle + arrowAngle),
            y: end.y - arrowLength * sin(forwardAngle + arrowAngle)
        ))
        // Second arrowhead at start for double style
        if arrowStyle == .double {
            let reverseAngle = forwardAngle + .pi
            path.move(to: start)
            path.addLine(to: CGPoint(
                x: start.x - arrowLength * cos(reverseAngle - arrowAngle),
                y: start.y - arrowLength * sin(reverseAngle - arrowAngle)
            ))
            path.move(to: start)
            path.addLine(to: CGPoint(
                x: start.x - arrowLength * cos(reverseAngle + arrowAngle),
                y: start.y - arrowLength * sin(reverseAngle + arrowAngle)
            ))
        }
        return path
    }
}
private enum OverlayGeometry {
    static let arrowHeadLength: CGFloat = 18
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
    @State private var dragGrabOffset: CGPoint?
    private let centerSize: CGFloat = 44
    private let primaryRadius: CGFloat = 88
    var body: some View {
        ZStack {
            if viewModel.isRadialExpanded {
                ringButtons(
                    items: viewModel.radialPrimaryItems,
                    radius: primaryRadius,
                    action: viewModel.selectPrimaryItem
                )
            }
            if viewModel.isOptionsOpen, let tool = viewModel.selectedToolForOptions {
                ToolOptionsPanelView(viewModel: viewModel, tool: tool)
                    .offset(y: primaryRadius + 72)
                    .onHover { isHovering in
                        if isHovering { viewModel.activateRadialControl() }
                    }
            }
            ZStack {
                Circle()
                    .fill(.black.opacity(0.75))
                Image(systemName: centerIconName)
                    .foregroundStyle(.white)
            }
            .frame(width: centerSize, height: centerSize)
            .help("Radial Control")
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("overlay"))
                    .onChanged { value in
                        if dragGrabOffset == nil {
                            dragGrabOffset = CGPoint(
                                x: value.startLocation.x - viewModel.radialCenter.x,
                                y: value.startLocation.y - viewModel.radialCenter.y
                            )
                        }
                        guard value.translation.length > 4 else { return }
                        viewModel.activateRadialControl()
                        let offset = dragGrabOffset ?? .zero
                        viewModel.moveRadialControl(
                            to: CGPoint(
                                x: value.location.x - offset.x,
                                y: value.location.y - offset.y
                            ),
                            in: availableSize
                        )
                    }
                    .onEnded { value in
                        let wasDrag = value.translation.length > 4
                        dragGrabOffset = nil
                        if wasDrag {
                            viewModel.scheduleRadialCollapse()
                        } else {
                            if viewModel.isRadialExpanded {
                                if let tool = viewModel.selectedToolForOptions, tool.hasConfigurableOptions {
                                    viewModel.toggleOptions()
                                } else {
                                    viewModel.collapseRadialControl()
                                }
                            } else {
                                viewModel.activateRadialControl()
                            }
                        }
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

    private var centerIconName: String {
        if !viewModel.isRadialExpanded { return "circle.grid.2x2.fill" }
        if let tool = viewModel.selectedToolForOptions, tool.hasConfigurableOptions {
            return viewModel.isOptionsOpen ? "xmark" : "paintpalette"
        }
        return "xmark"
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

private struct ToolOptionsPanelView: View {
    @ObservedObject var viewModel: OverlayViewModel
    let tool: ToolKind

    private let palette = ["#FF3B30FF", "#0A84FFFF", "#34C759FF", "#FFD60AFF", "#AF52DEFF", "#FFFFFFFF", "#FF9500FF"]

    var body: some View {
        VStack(spacing: 10) {
            Text(tool.rawValue.capitalized + " Options")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))

            colorSwatches

            if tool != .text {
                thicknessRow
            }

            if tool.hasLineStyleOption {
                lineStyleRow
            }

            if tool == .arrow {
                arrowStyleRow
            }

            if tool == .text {
                fontDesignRow
                fontSizeRow
            }

            HStack(spacing: 8) {
                Button("Cancel") { viewModel.cancelOptions() }
                    .buttonStyle(OptionsPillButtonStyle(isPrimary: false))
                Button("OK") { viewModel.confirmOptions() }
                    .buttonStyle(OptionsPillButtonStyle(isPrimary: true))
            }
        }
        .padding(12)
        .frame(width: 212)
        .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 12))
        .fixedSize(horizontal: false, vertical: true)
    }

    private var colorSwatches: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Color")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.55))
            HStack(spacing: 6) {
                ForEach(palette, id: \.self) { hex in
                    Button {
                        viewModel.pendingConfig.colorHexRGBA = hex
                    } label: {
                        Circle()
                            .fill(Color(hexRGBA: hex))
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle()
                                    .stroke(.white, lineWidth: viewModel.pendingConfig.colorHexRGBA == hex ? 2 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var thicknessRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Thickness: \(Int(viewModel.pendingConfig.strokeWidth))")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.55))
            Slider(value: $viewModel.pendingConfig.strokeWidth, in: 1...48, step: 1)
                .tint(.white)
        }
    }

    private var fontSizeRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Size: \(Int(viewModel.pendingConfig.strokeWidth))")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.55))
            Slider(value: $viewModel.pendingConfig.strokeWidth, in: 10...72, step: 2)
                .tint(.white)
        }
    }

    private var lineStyleRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Line Style")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.55))
            HStack(spacing: 4) {
                ForEach(LineStyle.allCases, id: \.self) { style in
                    Button {
                        viewModel.pendingExtendedOptions.lineStyle = style
                    } label: {
                        Text(style.displayName)
                            .font(.system(size: 11))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(
                                viewModel.pendingExtendedOptions.lineStyle == style
                                    ? Color.accentColor
                                    : Color.white.opacity(0.15),
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var arrowStyleRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Arrow")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.55))
            HStack(spacing: 4) {
                ForEach(ArrowStyle.allCases, id: \.self) { style in
                    Button {
                        viewModel.pendingExtendedOptions.arrowStyle = style
                    } label: {
                        Text(style.displayName)
                            .font(.system(size: 11))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(
                                viewModel.pendingExtendedOptions.arrowStyle == style
                                    ? Color.accentColor
                                    : Color.white.opacity(0.15),
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var fontDesignRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Font")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.55))
            HStack(spacing: 4) {
                ForEach(TextFontDesign.allCases, id: \.self) { design in
                    Button {
                        viewModel.pendingExtendedOptions.textFontDesign = design
                    } label: {
                        Text(design.displayName)
                            .font(.system(size: 11))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(
                                viewModel.pendingExtendedOptions.textFontDesign == design
                                    ? Color.accentColor
                                    : Color.white.opacity(0.15),
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct OptionsPillButtonStyle: ButtonStyle {
    let isPrimary: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: isPrimary ? .semibold : .regular))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                isPrimary
                    ? Color.accentColor.opacity(configuration.isPressed ? 0.7 : 1)
                    : Color.white.opacity(configuration.isPressed ? 0.2 : 0.12),
                in: RoundedRectangle(cornerRadius: 8)
            )
    }
}

private extension ToolKind {
    var hasConfigurableOptions: Bool {
        self != .eraser
    }
    var hasLineStyleOption: Bool {
        switch self {
        case .pen, .highlighter, .arrow, .rectangle, .ellipse: return true
        case .text, .eraser: return false
        }
    }
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
        case .applyToolOptions:
            return .toggleAnnotation // not displayed in radial tooltip; fallback
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
        case let .applyToolOptions(tool, _, _):
            return "applyToolOptions.\(tool.rawValue)"
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
        case let .applyToolOptions(tool, _, _):
            return "\(tool.rawValue.capitalized) Options"
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
            case .applyToolOptions:
                assertionFailure("applyToolOptions should not appear as a radial item")
                return "gear"
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
        case let .stroke(points, width, _, _, _):
            return point.distanceToPolyline(points) <= max(width * 0.5, 8)
        case let .arrow(start, end, width, _, _, _, _):
            return point.distanceToSegment(from: start, to: end) <= max(width * 0.6, 10)
        case let .rectangle(rect, width, _, _, _):
            return rect.insetBy(dx: -max(width, 10), dy: -max(width, 10)).contains(point)
        case let .ellipse(rect, width, _, _, _):
            let expanded = rect.insetBy(dx: -max(width, 10), dy: -max(width, 10))
            return expanded.contains(point)
        case let .text(text, center, fontSize, _, _, _):
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
private extension Array where Element == CGPoint {
    var boundingRect: CGRect {
        guard let first = first else { return .zero }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in dropFirst() {
            minX = Swift.min(minX, point.x)
            maxX = Swift.max(maxX, point.x)
            minY = Swift.min(minY, point.y)
            maxY = Swift.max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
private extension CGRect {
    static func normalized(from first: CGPoint, to second: CGPoint) -> CGRect {
        CGRect(
            x: Swift.min(first.x, second.x),
            y: Swift.min(first.y, second.y),
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
private extension TextFontDesign {
    var fontDesign: Font.Design {
        switch self {
        case .system: return .default
        case .serif: return .serif
        case .monospaced: return .monospaced
        }
    }
}
