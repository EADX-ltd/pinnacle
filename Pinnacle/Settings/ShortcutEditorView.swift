import SwiftUI

struct ShortcutEditorView: View {
    @ObservedObject var store: AppStore
    @State private var draft: [ShortcutBinding] = []

    private var conflictingSignatures: Set<String> {
        var seen: [String: Int] = [:]
        for binding in draft {
            seen[binding.signature, default: 0] += 1
        }
        return Set(seen.filter { $0.value > 1 }.keys)
    }

    private var hasConflicts: Bool { !conflictingSignatures.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if hasConflicts {
                Label(
                    "Two or more shortcuts share the same key combination. Resolve the conflict to save changes.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(draft.enumerated()), id: \.element.commandID) { index, binding in
                        ShortcutEditorRow(
                            binding: Binding(
                                get: { draft[index] },
                                set: { draft[index] = $0 }
                            ),
                            isConflicting: conflictingSignatures.contains(binding.signature)
                        )
                        if index < draft.count - 1 {
                            Divider()
                        }
                    }
                }
            }
            .frame(minHeight: 280)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .padding(16)
        .onAppear { loadFromStore() }
        .onChange(of: draft) { _, newDraft in
            // Live save when conflict-free; otherwise leave the draft local so
            // the user can edit out of the conflict before persisting.
            // Trade-off: every conflict-free toggle re-runs `unregisterAll()` +
            // 17×`RegisterEventHotKey`, so there's a brief window with no
            // active shortcuts. Acceptable while the user is editing in
            // Settings; if this becomes a hot path, debounce or move to a
            // commit-on-close model.
            guard !ShortcutConflictValidator.containsConflicts(newDraft) else { return }
            _ = store.updateShortcutBindings(newDraft)
        }
    }

    private func loadFromStore() {
        let stored = store.currentShortcutBindings
        // Order rows by the canonical default order so the list is stable
        // regardless of how user-edited bindings have been re-saved.
        let bindingByCommand = Dictionary(uniqueKeysWithValues: stored.map { ($0.commandID, $0) })
        draft = ShortcutCommandID.allCases.compactMap { bindingByCommand[$0] }
        // If stored is missing any command (e.g., schema drift), fall back to
        // the default for the missing entries.
        let missing = ShortcutCommandID.allCases.filter { bindingByCommand[$0] == nil }
        if !missing.isEmpty {
            let defaultByCommand = Dictionary(
                uniqueKeysWithValues: ShortcutBinding.defaults.map { ($0.commandID, $0) }
            )
            draft.append(contentsOf: missing.compactMap { defaultByCommand[$0] })
        }
    }
}

private struct ShortcutEditorRow: View {
    @Binding var binding: ShortcutBinding
    let isConflicting: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(binding.commandID.displayName)
                .frame(maxWidth: .infinity, alignment: .leading)

            ModifierToggles(modifiers: $binding.modifiers)

            Picker("", selection: $binding.key) {
                ForEach(ShortcutKey.allOrderedCases, id: \.self) { key in
                    Text(key.displayText).tag(key)
                }
            }
            .labelsHidden()
            .frame(width: 110)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            isConflicting
                ? Color.orange.opacity(0.10)
                : Color.clear
        )
    }
}

private struct ModifierToggles: View {
    @Binding var modifiers: ShortcutModifiers

    var body: some View {
        HStack(spacing: 4) {
            modifierToggle("⌃", flag: .control)
            modifierToggle("⌥", flag: .option)
            modifierToggle("⇧", flag: .shift)
            modifierToggle("⌘", flag: .command)
        }
    }

    private func modifierToggle(_ symbol: String, flag: ShortcutModifiers) -> some View {
        let isOn = modifiers.contains(flag)
        return Button(action: {
            if isOn {
                modifiers.remove(flag)
            } else {
                modifiers.insert(flag)
            }
        }) {
            Text(symbol)
                .font(.system(size: 13, weight: isOn ? .bold : .regular, design: .monospaced))
                .frame(width: 26, height: 22)
                .background(
                    isOn ? Color.accentColor.opacity(0.85) : Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 4)
                )
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}

extension ShortcutKey {
    /// Stable order for the editor picker so the list doesn't reshuffle.
    static var allOrderedCases: [ShortcutKey] {
        [.a, .c, .e, .p, .r, .z,
         .one, .two, .three, .four, .five, .six,
         .leftBracket, .rightBracket,
         .space, .backspace]
    }
}

// No SwiftUI #Preview here on purpose: instantiating an `AppStore(container:
// .live)` boots the real `AppKitShortcutService` (registers global Carbon
// hotkeys) and `ScreenCaptureKitRecordingService` every time the preview
// canvas opens. Validate via the running app instead.
