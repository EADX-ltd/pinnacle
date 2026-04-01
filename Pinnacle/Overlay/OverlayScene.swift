import CoreGraphics
import Foundation

struct OverlaySceneElement: Identifiable, Equatable {
    enum Kind: Equatable {
        case stroke(points: [CGPoint], width: CGFloat, colorHexRGBA: String, opacity: Double, lineStyle: LineStyle)
        case arrow(start: CGPoint, end: CGPoint, width: CGFloat, colorHexRGBA: String, opacity: Double, lineStyle: LineStyle, arrowStyle: ArrowStyle)
        case rectangle(rect: CGRect, width: CGFloat, colorHexRGBA: String, opacity: Double, lineStyle: LineStyle)
        case ellipse(rect: CGRect, width: CGFloat, colorHexRGBA: String, opacity: Double, lineStyle: LineStyle)
        case text(text: String, origin: CGPoint, fontSize: CGFloat, colorHexRGBA: String, opacity: Double, fontDesign: TextFontDesign)
    }

    let id: UUID
    var kind: Kind

    init(id: UUID = UUID(), kind: Kind) {
        self.id = id
        self.kind = kind
    }

    var colorHexRGBA: String {
        switch kind {
        case let .stroke(_, _, colorHexRGBA, _, _): return colorHexRGBA
        case let .arrow(_, _, _, colorHexRGBA, _, _, _): return colorHexRGBA
        case let .rectangle(_, _, colorHexRGBA, _, _): return colorHexRGBA
        case let .ellipse(_, _, colorHexRGBA, _, _): return colorHexRGBA
        case let .text(_, _, _, colorHexRGBA, _, _): return colorHexRGBA
        }
    }

    var opacity: Double {
        switch kind {
        case let .stroke(_, _, _, opacity, _): return opacity
        case let .arrow(_, _, _, _, opacity, _, _): return opacity
        case let .rectangle(_, _, _, opacity, _): return opacity
        case let .ellipse(_, _, _, opacity, _): return opacity
        case let .text(_, _, _, _, opacity, _): return opacity
        }
    }

    var lineWidth: CGFloat {
        switch kind {
        case let .stroke(_, width, _, _, _): return width
        case let .arrow(_, _, width, _, _, _, _): return width
        case let .rectangle(_, width, _, _, _): return width
        case let .ellipse(_, width, _, _, _): return width
        case .text: return 0
        }
    }
}

struct OverlayTextItem: Identifiable, Equatable {
    let id: UUID
    let text: String
    let origin: CGPoint
    let fontSize: CGFloat
    let colorHexRGBA: String
    let opacity: Double
    let fontDesign: TextFontDesign
}

struct TextDraft: Equatable {
    var text: String
    var origin: CGPoint
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

// MARK: - Hit Testing

extension OverlaySceneElement {
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
        case let .text(text, origin, fontSize, _, _, _):
            let bounds = CGRect(textOrigin: origin, text: text, fontSize: fontSize)
            return bounds.contains(point)
        }
    }
}

// MARK: - Geometry Helpers

extension CGPoint {
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

extension Array where Element == CGPoint {
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

extension CGRect {
    static func normalized(from first: CGPoint, to second: CGPoint) -> CGRect {
        CGRect(
            x: Swift.min(first.x, second.x),
            y: Swift.min(first.y, second.y),
            width: abs(first.x - second.x),
            height: abs(first.y - second.y)
        )
    }

    init(textOrigin: CGPoint, text: String, fontSize: CGFloat) {
        let estimatedWidth = max(44, CGFloat(text.count) * fontSize * 0.62)
        let estimatedHeight = max(24, fontSize * 1.5)
        self.init(
            x: textOrigin.x,
            y: textOrigin.y - (estimatedHeight * 0.5),
            width: estimatedWidth,
            height: estimatedHeight
        )
    }
}
