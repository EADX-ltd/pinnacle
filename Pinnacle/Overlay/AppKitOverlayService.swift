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
    private var passThroughControlPanelByDisplayID: [CGDirectDisplayID: OverlayPanel] = [:]
    private var activeDisplayID: CGDirectDisplayID?
    private var screenObserver: NSObjectProtocol?
    private var drawEventMonitor: Any?
    private var keyEventMonitor: Any?
    private var dragStartGlobalPoint: CGPoint?
    private var cancellables: Set<AnyCancellable> = []

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
        viewModel.onPassThroughModeChanged = { [weak self] isPassThrough in
            guard let self else { return }
            if isPassThrough {
                for panel in self.overlayPanelByDisplayID.values where NSApp.keyWindow === panel {
                    panel.resignKey()
                    break
                }
            } else {
                NSApp.activate(ignoringOtherApps: true)
                if let id = self.activeDisplayID, let panel = self.overlayPanelByDisplayID[id] {
                    panel.makeKey()
                }
            }
            self.refreshOverlayInteractionState()
        }
        bindViewModelState()
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
        viewModel.isPassThroughMode = false
        refreshOverlayInteractionState()
        orderActivePanelFront()
        NSApp.activate(ignoringOtherApps: true)
        if let id = activeDisplayID, let panel = overlayPanelByDisplayID[id] {
            panel.makeKey()
        }
        installMouseEventMonitor()
        installKeyEventMonitor()
        logger.log("Overlay started on display id=\(self.activeDisplayID ?? 0, privacy: .public)")
    }

    func stopOverlay() {
        viewModel.isOverlayVisible = false
        viewModel.isPassThroughMode = false
        viewModel.collapseRadialControl()
        refreshOverlayInteractionState()
        removeMouseEventMonitor()
        removeKeyEventMonitor()
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

    // MARK: - Panel management

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
        for (id, panel) in passThroughControlPanelByDisplayID {
            if id == targetID || targetID == nil {
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
            passThroughControlPanelByDisplayID[staleID]?.close()
            passThroughControlPanelByDisplayID[staleID] = nil
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
        refreshOverlayInteractionState()
    }

    private func makeOverlayPanel(for descriptor: DisplayDescriptor) -> OverlayPanel? {
        let panel = OverlayPanel(contentRect: descriptor.frame)
        let hosting = NSHostingView(
            rootView: OverlayRootView(
                viewModel: viewModel,
                coordinateTransformer: DisplayCoordinateTransformer(displayFrame: descriptor.frame)
            )
        )
        let container = PassThroughContainerView()
        container.viewModel = viewModel
        container.addSubview(hosting)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
        panel.contentView = container
        return panel
    }

    private func bindViewModelState() {
        viewModel.$isOverlayVisible
            .sink { [weak self] _ in
                self?.refreshOverlayInteractionState()
                self?.refreshCursor()
            }
            .store(in: &cancellables)

        viewModel.$isPassThroughMode
            .sink { [weak self] _ in
                self?.refreshOverlayInteractionState()
                self?.refreshCursor()
            }
            .store(in: &cancellables)

        viewModel.$toolState
            .sink { [weak self] _ in
                self?.refreshCursor()
            }
            .store(in: &cancellables)

        viewModel.$radialCenter
            .sink { [weak self] _ in
                self?.updatePassThroughControlPanelFrames()
            }
            .store(in: &cancellables)
    }

    private func refreshOverlayInteractionState() {
        let isClickThrough = viewModel.isOverlayVisible && viewModel.isPassThroughMode
        for panel in overlayPanelByDisplayID.values {
            panel.ignoresMouseEvents = isClickThrough
        }

        guard viewModel.isOverlayVisible else {
            removePassThroughControlPanels()
            return
        }

        if isClickThrough {
            synchronizePassThroughControlPanels()
            orderActivePanelFront()
        } else {
            removePassThroughControlPanels()
        }
    }

    private func synchronizePassThroughControlPanels() {
        let descriptors = NSScreen.screens.compactMap(\.displayDescriptor)
        let activeIDs = Set(descriptors.map(\.id))
        let staleIDs = Set(passThroughControlPanelByDisplayID.keys).subtracting(activeIDs)
        for staleID in staleIDs {
            passThroughControlPanelByDisplayID[staleID]?.close()
            passThroughControlPanelByDisplayID[staleID] = nil
        }

        for descriptor in descriptors {
            let layout = passThroughRadialPanelLayout(for: descriptor.frame)
            if let panel = passThroughControlPanelByDisplayID[descriptor.id] {
                if panel.frame != layout.frame {
                    panel.setFrame(layout.frame, display: true)
                }
                panel.orderFrontRegardless()
                continue
            }

            let panel = OverlayPanel(contentRect: layout.frame)
            let hosting = NSHostingView(
                rootView: PassThroughRadialPanelView(
                    viewModel: viewModel,
                    availableSize: layout.frame.size,
                    localCenter: layout.localCenter
                )
            )
            hosting.translatesAutoresizingMaskIntoConstraints = false
            let container = NSView(frame: CGRect(origin: .zero, size: layout.frame.size))
            container.addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.topAnchor.constraint(equalTo: container.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor)
            ])
            panel.contentView = container
            panel.orderFrontRegardless()
            passThroughControlPanelByDisplayID[descriptor.id] = panel
        }
    }

    private func removePassThroughControlPanels() {
        for panel in passThroughControlPanelByDisplayID.values {
            panel.orderOut(nil)
            panel.close()
        }
        passThroughControlPanelByDisplayID.removeAll()
    }

    private func updatePassThroughControlPanelFrames() {
        guard viewModel.isOverlayVisible, viewModel.isPassThroughMode else { return }
        let descriptorsByID = Dictionary(
            uniqueKeysWithValues: NSScreen.screens.compactMap(\.displayDescriptor).map { ($0.id, $0) }
        )
        for (displayID, panel) in passThroughControlPanelByDisplayID {
            guard let descriptor = descriptorsByID[displayID] else { continue }
            let layout = passThroughRadialPanelLayout(for: descriptor.frame)
            if panel.frame != layout.frame {
                panel.setFrame(layout.frame, display: true)
            }
            if let hosting = panel.contentView?.subviews.compactMap({ $0 as? NSHostingView<PassThroughRadialPanelView> }).first {
                hosting.rootView = PassThroughRadialPanelView(
                    viewModel: viewModel,
                    availableSize: layout.frame.size,
                    localCenter: layout.localCenter
                )
            }
        }
    }

    private func refreshCursor() {
        for panel in overlayPanelByDisplayID.values {
            guard let container = panel.contentView as? PassThroughContainerView else { continue }
            panel.invalidateCursorRects(for: container)
        }

        if viewModel.isOverlayVisible, !viewModel.isPassThroughMode, viewModel.toolState.activeTool == .eraser {
            NSCursor.pinnacleEraser.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func passThroughRadialPanelLayout(for displayFrame: CGRect) -> (frame: CGRect, localCenter: CGPoint) {
        let size = CGSize(width: 360, height: 460)
        let localCenter = CGPoint(x: size.width * 0.5, y: 128)
        let globalCenter = CGPoint(
            x: displayFrame.minX + viewModel.radialCenter.x,
            y: displayFrame.maxY - viewModel.radialCenter.y
        )
        let horizontalInset: CGFloat = 16
        let verticalInset: CGFloat = 16
        let minX = displayFrame.minX + horizontalInset
        let maxX = displayFrame.maxX - horizontalInset - size.width
        let minY = displayFrame.minY + verticalInset
        let maxY = displayFrame.maxY - verticalInset - size.height

        let frame = CGRect(
            x: min(max(globalCenter.x - localCenter.x, minX), maxX),
            y: min(max(globalCenter.y - (size.height - localCenter.y), minY), maxY),
            width: size.width,
            height: size.height
        )

        return (frame, localCenter)
    }

    // MARK: - Event monitoring

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

    private func installKeyEventMonitor() {
        guard keyEventMonitor == nil else { return }
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Escape
                Task { @MainActor [weak self] in self?.handleEscapeKey() }
                return nil
            }
            return event
        }
    }

    private func removeKeyEventMonitor() {
        guard let monitor = keyEventMonitor else { return }
        NSEvent.removeMonitor(monitor)
        keyEventMonitor = nil
    }

    private func handleEscapeKey() {
        if viewModel.isOptionsOpen {
            viewModel.cancelOptions()
        } else if viewModel.textDraft != nil {
            viewModel.cancelTextDraft()
        } else {
            viewModel.selectedToolForOptions = nil
            viewModel.enterPassThroughMode()
        }
    }

    private func handleOverlayMouseEvent(_ event: NSEvent) {
        guard viewModel.isOverlayVisible, !viewModel.isPassThroughMode else { return }
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

        let isShiftConstrained = event.modifierFlags.contains(.shift)

        switch event.type {
        case .leftMouseDown:
            dragStartGlobalPoint = globalPt
            viewModel.handleDragChanged(startLocation: globalPt, location: globalPt, isShiftConstrained: isShiftConstrained)
        case .leftMouseDragged:
            guard let startPt = dragStartGlobalPoint else { return }
            viewModel.handleDragChanged(startLocation: startPt, location: globalPt, isShiftConstrained: isShiftConstrained)
        case .leftMouseUp:
            let startPt = dragStartGlobalPoint ?? globalPt
            let translation = CGSize(width: globalPt.x - startPt.x, height: globalPt.y - startPt.y)
            viewModel.handleDragEnded(startLocation: startPt, location: globalPt, translation: translation, isShiftConstrained: isShiftConstrained)
            dragStartGlobalPoint = nil
        default:
            break
        }
    }
}
