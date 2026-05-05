import Combine
import Foundation

// Owns the text-draft lifecycle previously embedded in OverlayViewModel.
//
// Contract (encodes P4-T17 history):
// - `beginTextEditing` is the only path that sets `textDraft` non-nil; it
//   simultaneously snapshots the active config so options-panel changes do
//   not mutate the in-progress draft.
// - `commitTextDraft` clears state BEFORE invoking `onCommit` so callers
//   that synchronously start a new draft (e.g. clicking another text
//   location) do not race the cleared state.
// - `queueTextEditing(at:)` defers the new draft to the next runloop tick
//   when an existing draft is being committed, ensuring NSTextField has
//   torn down before a fresh field is mounted.
@MainActor
final class TextEditingViewModel: ObservableObject {
    @Published var textDraft: TextDraft?

    private(set) var textDraftConfig: ToolConfig?
    private(set) var textDraftExtendedOptions: ToolExtendedOptions?

    var configForActiveToolProvider: (() -> ToolConfig?)?
    var extendedOptionsForActiveToolProvider: (() -> ToolExtendedOptions?)?
    var onCommit: ((_ text: String, _ origin: CGPoint, _ config: ToolConfig, _ extOpts: ToolExtendedOptions) -> Void)?
    var onEditingActiveChanged: ((Bool) -> Void)?

    func queueTextEditing(at point: CGPoint) {
        let needsDeferredRestart = textDraft != nil
        if needsDeferredRestart {
            commitTextDraft()
            DispatchQueue.main.async { [weak self] in
                self?.beginTextEditing(at: point)
            }
            return
        }
        beginTextEditing(at: point)
    }

    func commitTextDraft() {
        guard let draft = textDraft else { return }
        let trimmed = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = textDraftConfig ?? configForActiveToolProvider?()
            ?? ToolConfig(colorHexRGBA: "#FFD60AFF", strokeWidth: 14, opacity: 1)
        let extOpts = textDraftExtendedOptions ?? extendedOptionsForActiveToolProvider?() ?? .default
        textDraft = nil
        textDraftConfig = nil
        textDraftExtendedOptions = nil
        onEditingActiveChanged?(false)
        guard !trimmed.isEmpty else { return }
        onCommit?(trimmed, draft.origin, config, extOpts)
    }

    func cancelTextDraft() {
        textDraft = nil
        textDraftConfig = nil
        textDraftExtendedOptions = nil
        onEditingActiveChanged?(false)
    }

    private func beginTextEditing(at point: CGPoint) {
        textDraftConfig = configForActiveToolProvider?()
        textDraftExtendedOptions = extendedOptionsForActiveToolProvider?()
        textDraft = TextDraft(text: "", origin: point)
        onEditingActiveChanged?(true)
    }
}
