import AppKit
import SwiftUI

struct OverlayRootView: View {
    @ObservedObject var viewModel: OverlayViewModel
    let coordinateTransformer: DisplayCoordinateTransformer

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.clear
                Canvas { context, _ in
                    for element in viewModel.sceneElements {
                        guard let localElement = localElement(for: element) else { continue }
                        render(element: localElement, in: &context)
                    }
                    if let previewElement = viewModel.previewElement {
                        if let localPreviewElement = localElement(for: previewElement) {
                            render(element: localPreviewElement, in: &context)
                        }
                    }
                }
                ForEach(Array(viewModel.textItems.enumerated()), id: \.element.id) { _, item in
                    if coordinateTransformer.displayFrame.contains(item.origin) {
                        let localOrigin = coordinateTransformer.globalPointToLocal(item.origin)
                        Text(item.text)
                            .font(.system(size: item.fontSize, weight: .semibold, design: item.fontDesign.fontDesign))
                            .foregroundStyle(Color(hexRGBA: item.colorHexRGBA).opacity(item.opacity))
                            .multilineTextAlignment(.leading)
                            .frame(width: 300, alignment: .leading)
                            .position(x: localOrigin.x + 150, y: localOrigin.y)
                            .allowsHitTesting(false)
                    }
                }
                if let textDraft = viewModel.textDraft, coordinateTransformer.displayFrame.contains(textDraft.origin) {
                    let fontSize = CGFloat(viewModel.textDraftActiveConfig.strokeWidth)
                    let nsColor = NSColor(Color(hexRGBA: viewModel.textDraftActiveConfig.colorHexRGBA).opacity(viewModel.textDraftActiveConfig.opacity))
                    let localOrigin = coordinateTransformer.globalPointToLocal(textDraft.origin)
                    OverlayTextField(
                        text: Binding(
                            get: { viewModel.textDraft?.text ?? "" },
                            set: { viewModel.textDraft?.text = $0 }
                        ),
                        draftID: textDraft.id,
                        font: .systemFont(ofSize: fontSize, weight: .semibold),
                        color: nsColor,
                        onCommit: { viewModel.commitTextDraft() }
                    )
                    .id(textDraft.id)
                    .frame(width: 300, height: fontSize * 1.5)
                    .position(x: localOrigin.x + 150, y: localOrigin.y)
                }
                if viewModel.isRadialControlEnabled && !viewModel.isPassThroughMode {
                    RadialControlView(viewModel: viewModel, availableSize: proxy.size)
                }
                HUDView(
                    text: viewModel.hudText,
                    color: viewModel.hudColor,
                    tooltip: viewModel.hudTooltip
                )
                .padding(20)
            }
            .coordinateSpace(name: "overlay")
            .onAppear {
                viewModel.ensureInitialRadialPosition(in: proxy.size)
            }
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
        case let .text(text, origin, fontSize, colorHexRGBA, opacity, fontDesign):
            guard coordinateTransformer.displayFrame.contains(origin) else { return nil }
            return OverlaySceneElement(
                id: element.id,
                kind: .text(
                    text: text,
                    origin: coordinateTransformer.globalPointToLocal(origin),
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
        guard let firstPoint = points.first else { return path }
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

struct PassThroughRadialPanelView: View {
    @ObservedObject var viewModel: OverlayViewModel
    let availableSize: CGSize
    let localCenter: CGPoint

    var body: some View {
        ZStack {
            Color.clear
            RadialControlView(
                viewModel: viewModel,
                availableSize: availableSize,
                centerOverride: localCenter,
                allowsRelocation: false
            )
        }
    }
}

enum OverlayGeometry {
    static let arrowHeadLength: CGFloat = 18
    static let radialCenterSize: CGFloat = 44
    static let radialPrimaryRingRadius: CGFloat = 88
    /// Hit-test / dead-zone radius when the radial control is collapsed.
    static let radialCollapsedRadius: CGFloat = 44
    /// Hit-test / dead-zone radius when the ring is expanded but options closed.
    static let radialExpandedRadius: CGFloat = 220
    /// Hit-test / dead-zone radius when the options panel is open below the ring.
    static let radialOptionsPanelRadius: CGFloat = 340
}

struct OverlayTextField: NSViewRepresentable {
    @Binding var text: String
    let draftID: UUID
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
        field.alignment = .left
        field.allowsEditingTextAttributes = false
        field.allowsCharacterPickerTouchBarItem = false
        field.delegate = context.coordinator
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    static func dismantleNSView(_ nsView: NSTextField, coordinator: Coordinator) {
        if let editor = nsView.currentEditor(), nsView.window?.firstResponder === editor {
            nsView.abortEditing()
            nsView.window?.makeFirstResponder(nil)
        } else if nsView.window?.firstResponder === nsView {
            nsView.window?.makeFirstResponder(nil)
        }
        nsView.delegate = nil
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        nsView.font = font
        nsView.textColor = color
        nsView.alignment = .left
        if nsView.stringValue != text { nsView.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: OverlayTextField
        init(_ parent: OverlayTextField) { self.parent = parent }

        func controlTextDidBeginEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField,
                  let textView = field.currentEditor() as? NSTextView else { return }
            textView.isAutomaticSpellingCorrectionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticDataDetectionEnabled = false
            textView.isAutomaticLinkDetectionEnabled = false
        }

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

extension Color {
    init(hexRGBA: ColorHex) {
        let value = hexRGBA.rawValue.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
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
