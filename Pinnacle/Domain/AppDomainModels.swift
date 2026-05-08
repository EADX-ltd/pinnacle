import Foundation

enum LineStyle: String, Codable, CaseIterable {
    case solid
    case dotted
    case dashed

    var displayName: String {
        switch self {
        case .solid: return "Solid"
        case .dotted: return "Dotted"
        case .dashed: return "Dashed"
        }
    }
}

enum ArrowStyle: String, Codable, CaseIterable {
    case single
    case double

    var displayName: String {
        switch self {
        case .single: return "Single"
        case .double: return "Double"
        }
    }
}

enum TextFontDesign: String, Codable, CaseIterable {
    case system
    case serif
    case monospaced

    var displayName: String {
        switch self {
        case .system: return "Sans"
        case .serif: return "Serif"
        case .monospaced: return "Mono"
        }
    }
}

struct ToolExtendedOptions: Equatable, Codable {
    var lineStyle: LineStyle
    var arrowStyle: ArrowStyle
    var textFontDesign: TextFontDesign

    static let `default` = ToolExtendedOptions(
        lineStyle: .solid,
        arrowStyle: .single,
        textFontDesign: .system
    )
}

enum SessionMode: Equatable {
    case idle
    case annotating
    case recording
    case recordingAndAnnotating
    case paused

    var displayName: String {
        switch self {
        case .idle:
            return "Idle"
        case .annotating:
            return "Annotating"
        case .recording:
            return "Recording"
        case .recordingAndAnnotating:
            return "Recording + Annotating"
        case .paused:
            return "Paused"
        }
    }
}

enum RadialPosition: String, Codable, CaseIterable {
    case right
    case left

    var displayName: String {
        switch self {
        case .right: return "Right"
        case .left: return "Left"
        }
    }
}

enum ToolKind: String, Codable, CaseIterable {
    case pen
    case highlighter
    case arrow
    case rectangle
    case ellipse
    case text
    case eraser
}

struct ColorHex: Equatable, Hashable, Codable, ExpressibleByStringLiteral, CustomStringConvertible {
    let rawValue: String

    init(_ rawValue: String) { self.rawValue = rawValue }
    init(stringLiteral value: String) { self.rawValue = value }

    init(from decoder: Decoder) throws {
        self.rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var description: String { rawValue }
}

struct ToolConfig: Equatable, Codable {
    var colorHexRGBA: ColorHex
    var strokeWidth: Double
    var opacity: Double
}

struct ToolState: Equatable, Codable {
    var activeTool: ToolKind
    var configs: [ToolKind: ToolConfig]
    var extendedOptions: [ToolKind: ToolExtendedOptions]

    static let `default` = ToolState(
        activeTool: .pen,
        configs: [
            .pen: ToolConfig(colorHexRGBA: "#FFD60AFF", strokeWidth: 1, opacity: 1),
            .highlighter: ToolConfig(colorHexRGBA: "#FFD60A66", strokeWidth: 14, opacity: 0.4),
            .arrow: ToolConfig(colorHexRGBA: "#0A84FFFF", strokeWidth: 1, opacity: 1),
            .rectangle: ToolConfig(colorHexRGBA: "#0A84FFFF", strokeWidth: 1, opacity: 1),
            .ellipse: ToolConfig(colorHexRGBA: "#0A84FFFF", strokeWidth: 1, opacity: 1),
            .text: ToolConfig(colorHexRGBA: "#FFD60AFF", strokeWidth: 14, opacity: 1),
            .eraser: ToolConfig(colorHexRGBA: "#00000000", strokeWidth: 0, opacity: 1)
        ],
        extendedOptions: ToolKind.allCases.reduce(into: [:]) { $0[$1] = .default }
    )
}
