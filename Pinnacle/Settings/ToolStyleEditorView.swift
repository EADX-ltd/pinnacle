import AppKit
import SwiftUI

struct ToolStyleEditorView: View {
    @ObservedObject var store: AppStore
    @State private var selectedTool: ToolKind = .pen

    private static let palette: [ColorHex] = [
        "#FF3B30FF", "#0A84FFFF", "#34C759FF", "#FFD60AFF",
        "#AF52DEFF", "#FFFFFFFF", "#FF9500FF"
    ]

    private var configurableTools: [ToolKind] {
        ToolKind.allCases.filter { $0.hasConfigurableOptions }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Tool", selection: $selectedTool) {
                ForEach(configurableTools, id: \.self) { tool in
                    Text(tool.rawValue.capitalized).tag(tool)
                }
            }
            .pickerStyle(.segmented)

            Form {
                Section {
                    colorRow
                    if selectedTool != .text {
                        thicknessRow
                    } else {
                        fontSizeRow
                    }
                    opacityRow
                }

                if selectedTool.hasLineStyleOption || selectedTool == .arrow || selectedTool == .text {
                    Section {
                        if selectedTool.hasLineStyleOption {
                            lineStyleRow
                        }
                        if selectedTool == .arrow {
                            arrowStyleRow
                        }
                        if selectedTool == .text {
                            fontDesignRow
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .padding(16)
    }

    // MARK: - Color

    private var colorRow: some View {
        let binding = Binding<ColorHex>(
            get: { store.currentToolConfig(for: selectedTool).colorHexRGBA },
            set: { newHex in
                var cfg = store.currentToolConfig(for: selectedTool)
                cfg.colorHexRGBA = newHex
                store.updateToolConfig(cfg, for: selectedTool)
            }
        )
        return LabeledContent("Color") {
            HStack(spacing: 8) {
                ForEach(Self.palette, id: \.self) { hex in
                    Button {
                        binding.wrappedValue = hex
                    } label: {
                        Circle()
                            .fill(Color(hexRGBA: hex))
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle()
                                    .stroke(
                                        binding.wrappedValue == hex ? Color.accentColor : Color.gray.opacity(0.3),
                                        lineWidth: binding.wrappedValue == hex ? 2 : 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
                ColorPicker(
                    "",
                    selection: Binding<Color>(
                        get: { Color(hexRGBA: binding.wrappedValue) },
                        set: { newColor in
                            if let hex = newColor.colorHexRGBA {
                                binding.wrappedValue = hex
                            }
                        }
                    ),
                    supportsOpacity: false
                )
                .labelsHidden()
            }
        }
    }

    // MARK: - Numerics

    private var thicknessRow: some View {
        let binding = Binding<Double>(
            get: { store.currentToolConfig(for: selectedTool).strokeWidth },
            set: { newWidth in
                var cfg = store.currentToolConfig(for: selectedTool)
                cfg.strokeWidth = newWidth
                store.updateToolConfig(cfg, for: selectedTool)
            }
        )
        return LabeledContent("Thickness") {
            HStack {
                Slider(value: binding, in: 1...48, step: 1)
                Text("\(Int(binding.wrappedValue))")
                    .frame(width: 32, alignment: .trailing)
                    .monospacedDigit()
            }
        }
    }

    private var fontSizeRow: some View {
        let binding = Binding<Double>(
            get: { store.currentToolConfig(for: selectedTool).strokeWidth },
            set: { newSize in
                var cfg = store.currentToolConfig(for: selectedTool)
                cfg.strokeWidth = newSize
                store.updateToolConfig(cfg, for: selectedTool)
            }
        )
        return LabeledContent("Font Size") {
            HStack {
                Slider(value: binding, in: 10...72, step: 2)
                Text("\(Int(binding.wrappedValue))")
                    .frame(width: 32, alignment: .trailing)
                    .monospacedDigit()
            }
        }
    }

    private var opacityRow: some View {
        let binding = Binding<Double>(
            get: { store.currentToolConfig(for: selectedTool).opacity },
            set: { newOpacity in
                var cfg = store.currentToolConfig(for: selectedTool)
                cfg.opacity = newOpacity
                store.updateToolConfig(cfg, for: selectedTool)
            }
        )
        return LabeledContent("Opacity") {
            HStack {
                Slider(value: binding, in: 0.1...1.0)
                Text(String(format: "%.0f%%", binding.wrappedValue * 100))
                    .frame(width: 40, alignment: .trailing)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Extended options

    private var lineStyleRow: some View {
        let binding = Binding<LineStyle>(
            get: { store.currentToolExtendedOptions(for: selectedTool).lineStyle },
            set: { newStyle in
                var opts = store.currentToolExtendedOptions(for: selectedTool)
                opts.lineStyle = newStyle
                store.updateToolExtendedOptions(opts, for: selectedTool)
            }
        )
        return LabeledContent("Line Style") {
            Picker("", selection: binding) {
                ForEach(LineStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var arrowStyleRow: some View {
        let binding = Binding<ArrowStyle>(
            get: { store.currentToolExtendedOptions(for: selectedTool).arrowStyle },
            set: { newStyle in
                var opts = store.currentToolExtendedOptions(for: selectedTool)
                opts.arrowStyle = newStyle
                store.updateToolExtendedOptions(opts, for: selectedTool)
            }
        )
        return LabeledContent("Arrow Style") {
            Picker("", selection: binding) {
                ForEach(ArrowStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var fontDesignRow: some View {
        let binding = Binding<TextFontDesign>(
            get: { store.currentToolExtendedOptions(for: selectedTool).textFontDesign },
            set: { newDesign in
                var opts = store.currentToolExtendedOptions(for: selectedTool)
                opts.textFontDesign = newDesign
                store.updateToolExtendedOptions(opts, for: selectedTool)
            }
        )
        return LabeledContent("Font") {
            Picker("", selection: binding) {
                ForEach(TextFontDesign.allCases, id: \.self) { design in
                    Text(design.displayName).tag(design)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}

// MARK: - Color → ColorHex bridge

private extension Color {
    /// Returns an `#RRGGBBAA` hex of this color in sRGB. Returns `nil` if the
    /// color can't be resolved (e.g., a system color that needs a context).
    var colorHexRGBA: ColorHex? {
        guard let nsColor = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = Int((nsColor.redComponent * 255).rounded())
        let g = Int((nsColor.greenComponent * 255).rounded())
        let b = Int((nsColor.blueComponent * 255).rounded())
        let a = Int((nsColor.alphaComponent * 255).rounded())
        return ColorHex(String(format: "#%02X%02X%02X%02X", r, g, b, a))
    }
}

// No SwiftUI #Preview here on purpose: see ShortcutEditorView for rationale.
