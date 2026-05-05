import AppKit
import Foundation

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

extension NSScreen {
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

extension DisplayDescriptor {
    static func underMouse() -> DisplayDescriptor? {
        let location = NSEvent.mouseLocation
        if let descriptor = NSScreen.screens.first(where: { $0.frame.contains(location) })?.displayDescriptor {
            return descriptor
        }
        return NSScreen.main?.displayDescriptor ?? NSScreen.screens.first?.displayDescriptor
    }
}
