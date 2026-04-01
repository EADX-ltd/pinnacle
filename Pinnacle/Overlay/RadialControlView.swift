import SwiftUI

struct RadialControlView: View {
    @ObservedObject var viewModel: OverlayViewModel
    let availableSize: CGSize
    var centerOverride: CGPoint? = nil
    var allowsRelocation = true

    @State private var dragGrabOffset: CGPoint?
    @State private var hoveredItem: OverlayViewModel.RadialItem?

    private let centerSize: CGFloat = 44
    private let primaryRadius: CGFloat = 88

    var body: some View {
        ZStack {
            if viewModel.isRadialExpanded {
                ringButtons(
                    items: viewModel.radialPrimaryItems,
                    radius: primaryRadius,
                    action: viewModel.selectPrimaryItem
                )
            }
            if viewModel.isOptionsOpen, let tool = viewModel.selectedToolForOptions {
                ToolOptionsPanelView(viewModel: viewModel, tool: tool)
                    .offset(y: primaryRadius + 72)
            }
            ZStack {
                Circle()
                    .fill(.black.opacity(0.75))
                Image(systemName: centerIconName)
                    .foregroundStyle(.white)
            }
            .frame(width: centerSize, height: centerSize)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("overlay"))
                    .onChanged { value in
                        guard allowsRelocation else { return }
                        if dragGrabOffset == nil {
                            dragGrabOffset = CGPoint(
                                x: value.startLocation.x - controlCenter.x,
                                y: value.startLocation.y - controlCenter.y
                            )
                        }
                        guard value.translation.length > 4 else { return }
                        viewModel.activateRadialControl()
                        let offset = dragGrabOffset ?? .zero
                        viewModel.moveRadialControl(
                            to: CGPoint(
                                x: value.location.x - offset.x,
                                y: value.location.y - offset.y
                            ),
                            in: availableSize
                        )
                    }
                    .onEnded { value in
                        dragGrabOffset = nil
                        guard value.translation.length <= 4 else { return }
                        if viewModel.isRadialExpanded {
                            if let tool = viewModel.selectedToolForOptions, tool.hasConfigurableOptions {
                                viewModel.toggleOptions()
                            } else {
                                viewModel.collapseRadialControl()
                            }
                        } else {
                            viewModel.activateRadialControl()
                        }
                    }
            )

            if let hovered = hoveredItem {
                Text(viewModel.tooltip(for: hovered))
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
                    .offset(y: -primaryRadius - 32)
                    .allowsHitTesting(false)
                    .transition(.opacity.animation(.easeInOut(duration: 0.1)))
            }
        }
        .position(controlCenter)
        .onHover { isHovering in
            if isHovering {
                viewModel.activateRadialControl()
            }
            if !isHovering { hoveredItem = nil }
        }
    }

    private var controlCenter: CGPoint {
        centerOverride ?? viewModel.radialCenter
    }

    private var centerIconName: String {
        if !viewModel.isRadialExpanded { return "circle.grid.2x2.fill" }
        if let tool = viewModel.selectedToolForOptions, tool.hasConfigurableOptions {
            return viewModel.isOptionsOpen ? "xmark" : "paintpalette"
        }
        return "xmark"
    }

    private func ringButtons(
        items: [OverlayViewModel.RadialItem],
        radius: CGFloat,
        action: @escaping (OverlayViewModel.RadialItem) -> Void
    ) -> some View {
        ZStack {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let angle = Double(index) / Double(max(items.count, 1)) * 2 * Double.pi
                Button {
                    action(item)
                } label: {
                    Image(systemName: item.symbolName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            viewModel.selectedToolForOptions.map { .tool($0) } == item
                                ? Color.accentColor : .white
                        )
                        .frame(width: 34, height: 34)
                        .background(.black.opacity(0.8), in: Circle())
                }
                .buttonStyle(.plain)
                .onHover { isHovering in
                    hoveredItem = isHovering ? item : nil
                }
                .offset(
                    x: CGFloat(cos(angle)) * radius,
                    y: CGFloat(sin(angle)) * radius
                )
            }
        }
    }
}
