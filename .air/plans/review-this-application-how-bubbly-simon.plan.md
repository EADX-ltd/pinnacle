# Pinnacle — Application Review & Improvement Plan

## Context

Pinnacle is a SwiftUI macOS menu-bar annotation/recording app (ZoomIt-like) targeting macOS 14+. The codebase is mid-flight: Phases 0–5 of an 11-phase roadmap are done, Phase 3 (annotation UX) is functionally complete but blocked on a manual GUI checklist (P3-T09), and Phases 6–9 (recording engine, settings UI, persistence, stabilization) are unstarted. This review captures the current state, surfaces concrete refinements ordered by priority, and lays out what remains to ship v1. The deliverable is the review document itself — no code is being changed in this plan.

## 1. Snapshot

- 23 Swift files, 3,275 LOC app + 784 LOC tests (~24% ratio)
- Largest file: `Pinnacle/Overlay/OverlayViewModel.swift` (522 LOC)
- Heaviest area: overlay rendering (49.5%)
- Phases complete: 0, 1, 2, 4, 5. In progress: 3 (blocked). Remaining: 6, 7, 8, 9.
- Architecture: `docs/ARCHITECTURE.md` (509 lines, decision log §13). Tasks: `docs/IMPLEMENTATION_TASKS.md` (54 tasks).

## 2. How It's Built

- **App/** — `AppContainer` (DI), `AppStore` (`@MainActor ObservableObject`, `send(CommandID)` → `reduce`).
- **Domain/** — `AppDomainModels`, `ShortcutModels` (17 defaults + conflict validator).
- **Services/** — protocol-first: shortcut (Carbon hotkeys, live), preferences (UserDefaults, live); recording + permissions are stubs.
- **Overlay/** — `AppKitOverlayService` (NSPanel), `OverlayViewModel`, `OverlayRootView` (Canvas), `OverlayScene` (undo/redo), radial + tool options.
- **Settings/**, **Recording/** — placeholders.

State flow: input → `AppStore.send` → `reduce` mutates `@Published sessionMode`/`toolState` → calls services → SwiftUI re-renders. Overlay-local state lives in `OverlayViewModel`.

Strengths: protocol services (mockable, well-tested state machine), clear `SessionMode` machine, multi-display coordinate handling in `DisplayCoordinateTransformer`, exemplary decision log.

## 3. Refinements (Prioritized)

### P0 — Structural debt
1. **Split `AppStore.reduce()`** (`AppStore.swift:87-163`) into `reduceAnnotationCommands` / `reduceRecordingCommands` / `reduceToolCommands`.
2. **Make radial state explicit** — replace four bools (`isRadialExpanded`, `isPassThroughMode`, `selectedToolForOptions`, `isOptionsOpen`) with `enum RadialState { collapsed, expanded, optionsOpen(ToolKind), passThrough }`.
3. **Extract `TextEditingViewModel`** from the 522-LOC `OverlayViewModel`; isolates the NSTextField responder lifecycle that already caused P4-T17 incidents.
4. **Propagate overlay errors** — `AppKitOverlayService.startOverlay()` silently logs panel-creation failure; surface via `AppStore.lastErrorMessage`.

### P1 — Type/API hygiene
5. `ColorHex` newtype to replace raw `"#FFD60AFF"` strings in `ToolConfig`.
6. `AppContainer.live` as `@MainActor static let` (currently a computed property — risks orphaned hotkey registrations).
7. Consolidate duplicated `globalPointToLocal` logic into one extension.

### P2 — Documentation
8. Inline docs on `OverlayViewModel.handleDragChanged` and the global-vs-local coordinate boundary.
9. Encode the text-editing responder lifecycle as a contract comment (P4-T17 history).
10. Audit `[weak self]` and `removeObserver` paths in `AppKitOverlayService`.

## 4. What Remains (Phase Roadmap)

- **Phase 3 (unblock)** — P3-T09 manual GUI checklist on Xcode runtime.
- **Phase 6** — ScreenCaptureKit + AVAssetWriter, real `RecordingService`, real `PermissionService` (Screen Recording + Accessibility), async error propagation.
- **Phase 7** — Settings UI: shortcut editor (key-learn + conflict), tool palette editor, permissions panel; mocks first.
- **Phase 8** — Persist `ToolState` with schema versioning; recording output dir + deterministic naming + optional JSON sidecar.
- **Phase 9** — Perf baselines (<16 ms stroke p99, <1.5 s startup, 1080p@30 / 30 min stability), full manual matrix, visual-regression tests, release doc.

## 5. Execution Steps

1. Unblock P3-T09 (manual checklist in Xcode).
2. Land P0 refactors in order: reduce() split → RadialState enum → TextEditingViewModel extraction → overlay error surfacing.
3. P1 hygiene: ColorHex, AppContainer singleton, coordinate-transform consolidation.
4. Phase 6 kickoff — `RecordingService` design doc, break into P6-T01..T06.
5. Phase 7 — UI mocks then implementation.
6. Phase 8 — `ToolState` persistence + output manager.
7. Phase 9 — perf, matrix, visual regression, release doc.

Update `docs/ARCHITECTURE.md §13` and `docs/IMPLEMENTATION_TASKS.md` after each phase (exactly one `in_progress` task per CLAUDE.md).

## 6. Verification

- `xcodebuild test -scheme Pinnacle` — all `PinnacleSmokeTests` green after each refactor.
- P3-T09 manual run on single + dual display (mixed scale).
- Phase 6: record 60 s clip, play in QuickTime, no artifacts.
- Phase 8: old-schema preferences migrate without data loss.
- Phase 9: `os_signpost` instrumentation, p99 stroke latency in Instruments.

## 7. Critical Files

- `Pinnacle/App/AppStore.swift` — reduce() split, error surfacing.
- `Pinnacle/Overlay/OverlayViewModel.swift` — RadialState enum, text extraction, docs.
- `Pinnacle/Overlay/AppKitOverlayService.swift` — error propagation, observer audit.
- `Pinnacle/Domain/AppDomainModels.swift` — `ColorHex` newtype.
- `Pinnacle/App/AppContainer.swift` — singleton lifecycle.
- `Pinnacle/Services/` — new `ScreenCaptureRecordingService.swift`, real `PermissionService` (Phase 6).
- `Pinnacle/Settings/SettingsView.swift` — full UI (Phase 7).
- `docs/ARCHITECTURE.md`, `docs/IMPLEMENTATION_TASKS.md` — keep current.

The full review document is at [review-this-application-how-bubbly-simon.md](air-file://j5buvobd4p5aarpfpsjn/Users/zhivko/.claude/plans/review-this-application-how-bubbly-simon.md?type=file&root=%252F).