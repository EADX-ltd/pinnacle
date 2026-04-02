import AppKit

final class OverlayPanel: NSPanel {
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

// In pass-through mode routes mouse events only to the HUD and radial control areas;
// all other areas are transparent to clicks so users can interact with apps below.
final class PassThroughContainerView: NSView {
    weak var viewModel: OverlayViewModel?

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let viewModel,
              viewModel.isOverlayVisible,
              !viewModel.isPassThroughMode,
              viewModel.toolState.activeTool == .eraser
        else { return }
        addCursorRect(bounds, cursor: .pinnacleEraser)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let vm = viewModel, vm.isPassThroughMode else {
            return super.hitTest(point)
        }
        // AppKit uses Y-up; SwiftUI layout uses Y-down from the top-left origin.
        let swiftUIPoint = CGPoint(x: point.x, y: bounds.height - point.y)

        // HUD pill lives at top-left with .padding(20).
        let hudRect = CGRect(x: 10, y: 10, width: 240, height: 54)
        if hudRect.contains(swiftUIPoint) {
            return super.hitTest(point)
        }

        // Radial control – include ring radius plus options panel height when open.
        let radialCenter = vm.radialCenter
        let outerRadius: CGFloat = vm.isOptionsOpen ? 340 : (vm.isRadialExpanded ? 220 : 44)
        if hypot(swiftUIPoint.x - radialCenter.x, swiftUIPoint.y - radialCenter.y) < outerRadius {
            return super.hitTest(point)
        }

        return nil
    }
}
extension NSCursor {
    static let pinnacleEraser: NSCursor = {
        guard let symbol = NSImage(
            systemSymbolName: "eraser.fill",
            accessibilityDescription: "Eraser"
        )?.withSymbolConfiguration(.init(pointSize: 18, weight: .medium)) else {
            return .crosshair
        }
        let image = NSImage(size: NSSize(width: 32, height: 32))
        image.lockFocus()
        NSColor.clear.set()
        NSBezierPath(rect: NSRect(origin: .zero, size: image.size)).fill()
        NSColor.systemRed.set()
        symbol.draw(in: NSRect(x: 6, y: 6, width: 20, height: 20))
        image.unlockFocus()
        return NSCursor(image: image, hotSpot: NSPoint(x: 8, y: 8))
    }()
}
