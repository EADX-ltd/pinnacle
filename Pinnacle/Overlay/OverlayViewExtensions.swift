import Foundation
import SwiftUI

// MARK: - ToolKind overlay helpers

extension ToolKind {
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

// MARK: - OverlayAction display helpers

extension OverlayAction {
    var shortcutCommandID: ShortcutCommandID {
        switch self {
        case let .selectTool(tool): return tool.shortcutCommandID
        case .undo: return .undo
        case .redo: return .redo
        case .clearAll: return .clearAll
        case .cycleColors: return .cycleColors
        case .increaseStroke: return .increaseStroke
        case .decreaseStroke: return .decreaseStroke
        case .applyToolOptions: return .toggleAnnotation // fallback; not shown in radial tooltip
        }
    }

    var id: String {
        switch self {
        case let .selectTool(tool): return "selectTool.\(tool.rawValue)"
        case .undo: return "undo"
        case .redo: return "redo"
        case .clearAll: return "clearAll"
        case .cycleColors: return "cycleColors"
        case .increaseStroke: return "increaseStroke"
        case .decreaseStroke: return "decreaseStroke"
        case let .applyToolOptions(tool, _, _): return "applyToolOptions.\(tool.rawValue)"
        }
    }

    var label: String {
        switch self {
        case let .selectTool(tool): return tool.rawValue.capitalized
        case .undo: return "Undo"
        case .redo: return "Redo"
        case .clearAll: return "Clear All"
        case .cycleColors: return "Cycle Colors"
        case .increaseStroke: return "Increase Stroke"
        case .decreaseStroke: return "Decrease Stroke"
        case let .applyToolOptions(tool, _, _): return "\(tool.rawValue.capitalized) Options"
        }
    }
}

// MARK: - RadialItem display helpers

extension OverlayViewModel.RadialItem {
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

// MARK: - ShortcutCommandID display

extension ShortcutCommandID {
    var displayName: String {
        switch self {
        case .toggleAnnotation: return "Toggle Annotation"
        case .toggleRecording: return "Start / Stop Recording"
        case .togglePauseRecording: return "Pause / Resume Recording"
        case .selectPen: return "Tool: Pen"
        case .selectHighlighter: return "Tool: Highlighter"
        case .selectArrow: return "Tool: Arrow"
        case .selectRectangle: return "Tool: Rectangle"
        case .selectEllipse: return "Tool: Ellipse"
        case .selectText: return "Tool: Text"
        case .selectEraser: return "Tool: Eraser"
        case .undo: return "Undo"
        case .redo: return "Redo"
        case .clearAll: return "Clear All"
        case .cycleColors: return "Cycle Colors"
        case .increaseStroke: return "Increase Stroke"
        case .decreaseStroke: return "Decrease Stroke"
        case .toggleRadialControl: return "Toggle Radial Control"
        }
    }
}

// MARK: - ShortcutBinding display text

extension ShortcutBinding {
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

extension ShortcutKey {
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

extension TextFontDesign {
    var fontDesign: Font.Design {
        switch self {
        case .system:
            return .default
        case .serif:
            return .serif
        case .monospaced:
            return .monospaced
        }
    }
}
