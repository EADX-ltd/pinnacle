import SwiftUI

struct HUDView: View {
    let text: String
    let color: Color
    let tooltip: String

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                Text(text)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.65), in: Capsule())
            .onHover { isHovered = $0 }

            if isHovered {
                Text(tooltip)
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
                    .allowsHitTesting(false)
                    .transition(.opacity.animation(.easeInOut(duration: 0.1)))
            }
        }
    }
}
