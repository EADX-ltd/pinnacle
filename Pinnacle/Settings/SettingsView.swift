import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pinnacle Settings")
                .font(.title3.weight(.semibold))
            Text("Settings UI will be implemented in Phase 7.")
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(minWidth: 360, minHeight: 140)
    }
}

#Preview {
    SettingsView()
}
