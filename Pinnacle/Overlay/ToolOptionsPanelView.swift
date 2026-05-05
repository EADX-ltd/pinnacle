import SwiftUI

struct ToolOptionsPanelView: View {
    @ObservedObject var viewModel: OverlayViewModel
    let tool: ToolKind

    private let palette: [ColorHex] = ["#FF3B30FF", "#0A84FFFF", "#34C759FF", "#FFD60AFF", "#AF52DEFF", "#FFFFFFFF", "#FF9500FF"]

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
        .overlay(alignment: .topTrailing) {
            Button {
                viewModel.cancelOptions()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .red)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .padding(6)
        }
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

struct OptionsPillButtonStyle: ButtonStyle {
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
