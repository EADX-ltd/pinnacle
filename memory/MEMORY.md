# Pinnacle Project Memory

## Project
macOS menu bar annotation app. SwiftUI + AppKit hybrid. See CLAUDE.md for structure.

## Key Architecture
- `AppStore` (@MainActor, ObservableObject) is the single source of truth. Sends commands via `CommandID`.
- `AppContainer` is the DI root. Services injected via protocols.
- `AppKitOverlayService` owns the overlay panels and `OverlayViewModel`.
- `OverlayViewModel` owns scene model, radial control state, and options panel state.
- `OverlayAction` enum routes overlay events back to `AppStore` (command handler pattern).

## Domain Model (AppDomainModels.swift)
- `ToolState` contains `configs: [ToolKind: ToolConfig]` AND `extendedOptions: [ToolKind: ToolExtendedOptions]`.
- `ToolExtendedOptions` has `lineStyle: LineStyle`, `arrowStyle: ArrowStyle`, `textFontDesign: TextFontDesign`.
- `LineStyle`: solid/dotted/dashed. `ArrowStyle`: single/double. `TextFontDesign`: system/serif/monospaced.
- Defaults via `ToolKind.allCases.reduce(into:)`.

## Overlay / Radial UX
- Radial control: hover-activated, **no auto-collapse** (timer removed). Stays expanded until Escape or center tap.
- No secondary ring. Tool selection sets `selectedToolForOptions`.
- Center icon: grid (collapsed) → xmark (expanded, no tool/eraser) → paintpalette (expanded, configurable tool).
- Tapping center with configurable tool selected toggles `ToolOptionsPanelView`.
- Options panel uses `pendingConfig` and `pendingExtendedOptions` (both @Published on OverlayViewModel).
- OK → `confirmOptions()` → updates local toolState + dispatches `.applyToolOptions` action.
- Cancel / red `×` button → `cancelOptions()` → discards.
- Custom `@State hoveredItem` tooltip overlays replace `.help()` (unreliable in non-activating panels).

## Pass-Through Mode (Escape key)
- Escape: cancel options → cancel text draft → deselect tool → `enterPassThroughMode()`.
- `enterPassThroughMode()`: sets `isPassThroughMode = true`, calls `onPassThroughModeChanged(true)`.
- `AppKitOverlayService` toggles `panel.ignoresMouseEvents = true` for all panels.
- `PassThroughContainerView` overrides `hitTest` to only allow hits in HUD (top-left ~240×54) and radial area.
- Clicking any radial tool → `exitPassThroughMode()` → panels interactive again.
- App is activated and panel made key on `startOverlay()` so local key monitor works.

## Text Editing Config Snapshot
- `beginTextEditing` saves `textDraftConfig` and `textDraftExtendedOptions` snapshot.
- `commitTextDraft` uses snapshot; color/font/size frozen at edit-start time.
- `cancelTextDraft()` clears draft + snapshot + calls `onTextEditingActive(false)`.
- `OverlayRootView` uses `viewModel.textDraftActiveConfig` for live rendering of in-progress text.

## Scene Element Model
- `OverlaySceneElement.Kind` stores `lineStyle: LineStyle` in stroke/arrow/rect/ellipse.
- Arrow also stores `arrowStyle: ArrowStyle`.
- Text stores `fontDesign: TextFontDesign`.
- `makeStrokeStyle(width:lineStyle:cap:join:)` applies dash patterns.
- `makeArrowPath(start:end:arrowStyle:)` adds second arrowhead for `.double`.

## Test Setup
- `SpyOverlayService` in tests tracks start/stop/undo/redo/clearAll/toolState.
- Tests use `makeStoreHarness()` to build isolated container.
- `xcodebuild` unavailable (CommandLineTools). All validation is static + test compilation.

## Current Phase Status
- Phase 3 `in_progress` — blocked on P3-T09 (manual GUI checklist in macOS runtime).
- Phase 4 `done`.
- Phase 5 `done`.
- Next: P3-T09 unblocks → Phase 3 done → Phase 6 (Recording engine).

## Common Pitfalls
- A linter in this environment can revert `AppStore.swift` to an older version — always check/restore it.
- `ToolState.default` uses `ToolKind.allCases.reduce(into:)` which requires `CaseIterable` on `ToolKind`.
