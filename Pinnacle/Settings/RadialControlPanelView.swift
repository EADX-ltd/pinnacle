import SwiftUI

struct RadialControlPanelView: View {
    @ObservedObject var store: AppStore

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { store.isRadialControlEnabled },
            set: { store.setRadialControlEnabled($0) }
        )
    }

    private var positionBinding: Binding<RadialPosition> {
        Binding(
            get: { store.radialDefaultPosition },
            set: { store.setRadialDefaultPosition($0) }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("Show radial control on overlay", isOn: enabledBinding)
                LabeledContent("Why this is here") {
                    Text("The radial control floats on the annotation overlay and lets you switch tools and trigger actions without keyboard shortcuts. Disabling it hides the control; you can still use shortcuts.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Radial Control")
            }

            Section {
                Picker("Default position", selection: positionBinding) {
                    ForEach(RadialPosition.allCases, id: \.self) { position in
                        Text(position.displayName).tag(position)
                    }
                }
                .pickerStyle(.segmented)
                LabeledContent("") {
                    Text("Where the radial appears the first time it's shown in a session. You can drag it anywhere afterwards.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Position")
            }
        }
        .formStyle(.grouped)
        .padding(16)
    }
}

// No SwiftUI #Preview here on purpose: see ShortcutEditorView for rationale.
