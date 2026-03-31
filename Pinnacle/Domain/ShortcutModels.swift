import Foundation

enum ShortcutCommandID: String, Codable, CaseIterable {
    case toggleAnnotation
    case toggleRecording
    case togglePauseRecording
    case selectPen
    case selectHighlighter
    case selectArrow
    case selectRectangle
    case selectEllipse
    case selectText
    case selectEraser
    case undo
    case redo
    case clearAll
    case cycleColors
    case increaseStroke
    case decreaseStroke
    case toggleRadialControl
}

struct ShortcutModifiers: OptionSet, Hashable, Codable {
    let rawValue: UInt8

    static let control = ShortcutModifiers(rawValue: 1 << 0)
    static let option = ShortcutModifiers(rawValue: 1 << 1)
    static let shift = ShortcutModifiers(rawValue: 1 << 2)
    static let command = ShortcutModifiers(rawValue: 1 << 3)
}

enum ShortcutKey: String, Codable, Hashable {
    case a
    case r
    case p
    case one
    case two
    case three
    case four
    case five
    case six
    case e
    case z
    case c
    case leftBracket
    case rightBracket
    case backspace
    case space
}

struct ShortcutBinding: Codable, Equatable, Hashable {
    var commandID: ShortcutCommandID
    var key: ShortcutKey
    var modifiers: ShortcutModifiers

    var signature: String {
        "\(key.rawValue)#\(modifiers.rawValue)"
    }
}

extension ShortcutBinding {
    static let defaults: [ShortcutBinding] = [
        ShortcutBinding(commandID: .toggleAnnotation, key: .a, modifiers: [.control, .option]),
        ShortcutBinding(commandID: .toggleRecording, key: .r, modifiers: [.control, .option]),
        ShortcutBinding(commandID: .togglePauseRecording, key: .p, modifiers: [.control, .option]),
        ShortcutBinding(commandID: .selectPen, key: .one, modifiers: [.control, .option]),
        ShortcutBinding(commandID: .selectHighlighter, key: .two, modifiers: [.control, .option]),
        ShortcutBinding(commandID: .selectArrow, key: .three, modifiers: [.control, .option]),
        ShortcutBinding(commandID: .selectRectangle, key: .four, modifiers: [.control, .option]),
        ShortcutBinding(commandID: .selectEllipse, key: .five, modifiers: [.control, .option]),
        ShortcutBinding(commandID: .selectText, key: .six, modifiers: [.control, .option]),
        ShortcutBinding(commandID: .selectEraser, key: .e, modifiers: [.control, .option]),
        ShortcutBinding(commandID: .undo, key: .z, modifiers: [.control, .option]),
        ShortcutBinding(commandID: .redo, key: .z, modifiers: [.control, .option, .shift]),
        ShortcutBinding(commandID: .clearAll, key: .backspace, modifiers: [.control, .option]),
        ShortcutBinding(commandID: .cycleColors, key: .c, modifiers: [.control, .option]),
        ShortcutBinding(commandID: .increaseStroke, key: .rightBracket, modifiers: [.control, .option]),
        ShortcutBinding(commandID: .decreaseStroke, key: .leftBracket, modifiers: [.control, .option]),
        ShortcutBinding(commandID: .toggleRadialControl, key: .space, modifiers: [.control, .option])
    ]
}

enum ShortcutConflictValidator {
    static func containsConflicts(_ bindings: [ShortcutBinding]) -> Bool {
        var signatures = Set<String>()
        for binding in bindings {
            if signatures.contains(binding.signature) {
                return true
            }
            signatures.insert(binding.signature)
        }
        return false
    }

    static func resolvedBindings(_ candidate: [ShortcutBinding]) -> [ShortcutBinding] {
        if containsConflicts(candidate) {
            return ShortcutBinding.defaults
        }
        return candidate
    }
}
