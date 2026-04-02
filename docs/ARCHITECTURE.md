# Pinnacle Architecture

## 1. Goal
Build a macOS menu bar app that mimics ZoomIt-style screen annotation and recording, with a SwiftUI control surface, global keyboard shortcuts, and configurable tool colors.

## 2. Product Scope
- Platform: macOS 14+ (preferred, due to `ScreenCaptureKit` maturity).
- App style: menu bar app (`MenuBarExtra`) with optional settings window.
- Core features:
  - Real-time screen annotation overlay.
  - Screen recording (display only in v1; audio optional in v2).
  - Tool switching via global shortcuts.
  - Tool-specific default colors and stroke sizes.
  - Persistent preferences.

Out of scope for v1:
- Cloud sync.
- Collaboration/live sharing.
- OCR or AI-assisted annotation.

## 3. High-Level Architecture

```text
+----------------------+       +-----------------------+
| SwiftUI Menu Bar UI  |<----->| App State Store       |
| (MenuBarExtra +      |       | (Observable +         |
| Settings scenes)     |       | persistence adapter)  |
+----------+-----------+       +-----------+-----------+
           |                               |
           v                               v
+----------+-----------+       +-----------+-----------+
| Shortcut Manager     |       | Permission Manager     |
| (global hotkeys)     |       | (Screen Recording,     |
|                       |       | Accessibility)         |
+----------+-----------+       +-----------+-----------+
           |                               |
           +---------------+---------------+
                           v
                 +---------+----------+
                 | Session Orchestrator|
                 | (idle/annotating/   |
                 | recording/paused)   |
                 +-----+----------+----+
                       |          |
             +---------+          +--------------------+
             v                                       v
+------------+-------------+          +-------------+--------------+
| Overlay Engine           |          | Recording Engine            |
| (NSWindow/NSPanel,       |          | (ScreenCaptureKit +         |
| drawing tools, hit-test) |          | AVAssetWriter pipeline)     |
+------------+-------------+          +-------------+--------------+
             |                                        |
             v                                        v
      +------+----------------+               +-------+--------------+
      | Tool Renderers        |               | File Storage Service |
      | (pen/shape/text/etc.) |               | (recordings, metadata)|
      +-----------------------+               +----------------------+
```

## 4. Module Breakdown

### 4.1 UI Layer (`SwiftUI`)
- `MenuBarScene`: start/stop annotation, start/stop recording, quick tool select.
- `SettingsScene`: shortcuts, colors, stroke widths, save location, behavior toggles.
- `HUDOverlayView` (optional): small floating indicator for current tool/color with hover tooltip showing action name and key binding.
- `RadialControlOverlay` (optional but recommended): compact center circle that expands to a first donut ring of tools; tool options are shown in a contextual panel (no shared second ring).

### 4.2 App State and Domain
- `AppSessionState`: `idle`, `annotating`, `recording`, `recordingAndAnnotating`, `paused`.
- `ToolState`: current tool, color, stroke width, opacity.
- `RecordingState`: target display, file URL, elapsed time, encoder status.
- `PreferencesState`: shortcut map, color palette, defaults.

Recommended pattern:
- Single source of truth (`AppStore`) using `@MainActor` observable object.
- Engine services injected through protocols for testability.

### 4.3 Shortcut Manager
- Registers global hotkeys using a stable macOS API/library (e.g., Carbon hotkey APIs or vetted package).
- Maps key combinations to domain commands (`CommandID` enum).
- Prevents collisions and supports user remapping with validation.

### 4.4 Overlay Engine
- Creates one transparent overlay window for the display under the mouse when annotation starts.
- Window level above normal apps; click-through disabled only while annotating.
- Handles pointer input and routes events to selected tool renderer.
- Maintains vector model of strokes/shapes for redraw and undo/redo.

### 4.5 Recording Engine
- Uses `ScreenCaptureKit` for display capture.
- Encodes video via `AVAssetWriter`.
- Syncs with overlay state:
  - v1 option A: capture full display including overlay windows.
  - v1 option B: compose captured frames + annotation layer (higher complexity).

Recommendation for v1:
- Use option A to reduce complexity and ship earlier.

### 4.6 Permission Manager
- Checks and requests:
  - Screen Recording permission.
  - Accessibility permission (if needed for event taps/global input behavior).
- Exposes status and actionable guidance in settings UI.

### 4.7 Persistence
- `UserDefaults` for shortcuts, colors, preferences.
- File system for recordings and optional exported snapshots.
- Save output directory configurable; validate write permission before start.

### 4.8 Radial Control Purpose and UX Contract
Purpose:
- Provide an in-session command surface so users can annotate effectively without relying only on keyboard shortcuts.
- Offer fast access to high-frequency actions: tool switch, color select, stroke size, undo/redo, clear.
- Improve discoverability by exposing shortcut hints via hover tooltips.

Non-goals:
- Do not replace full settings/configuration UI.
- Do not obstruct drawing input or recording content more than necessary.

Behavior contract:
- Available in annotation mode; toggleable by shortcut/menu.
- Default state is a single small collapsed circle.
- Hovering the center circle activates control (expands permanently — no auto-collapse timer).
- Activated control expands the first donut ring of tools around the center circle.
- Hovering a tool in the first ring shows a custom floating tooltip with the tool name + shortcut.
- Clicking a tool selects it and replaces center `X` with an options-trigger icon (color-picker icon).
- Clicking the options-trigger icon opens options for the selected tool in a panel below the first ring.
- The options panel is anchored to the radial control and moves together with it.
- Options panel has an `OK`, `Cancel`, and a red `×` close button (all equivalent to Cancel).
- `OK` applies changes and stores them as last-used settings for that tool.
- `Cancel`/`×` discards pending changes and keeps previously saved settings.
- Closing options (`OK` or `Cancel`/`×`) returns center icon to `X`.
- Control never auto-collapses; it stays expanded until explicitly dismissed (Escape key or center tap).
- Draggable with edge snap and remembers last position.
- Pass-through interaction outside control bounds.
- If a tool has no configurable options, options-trigger icon remains hidden/disabled for that tool.

### 4.9 Escape Key and Pass-Through Mode
- Pressing **Escape** while options panel is open → cancels and closes options panel.
- Pressing **Escape** while text tool is being edited → cancels in-progress text element.
- Pressing **Escape** in normal annotation mode → deselects current radial tool selection and enters **pass-through mode**.
- **Pass-through mode**: overlay panels set `ignoresMouseEvents = true`; drawn annotations remain visible; only the HUD pill and radial control area remain interactive via per-area `hitTest` in `PassThroughContainerView`.
- Clicking any tool in the radial control while in pass-through mode → exits pass-through and returns to annotation mode.
- Text element color/font/size are snapshotted at edit-begin time and are unaffected by tool-config changes made during typing.

## 5. Tooling Model

## 5.1 Tool Set (v1)
- `Pen`
- `Highlighter`
- `Arrow`
- `Rectangle`
- `Ellipse`
- `Text`
- `Eraser` (object erase, not pixel erase)
- `Clear All`

## 5.2 Default Color and Style Map
Use named palette tokens so themes can change without rewriting tool logic.

| Tool | Token | Default RGBA | Notes |
|---|---|---|---|
| Pen | `tool.pen` | `#FF3B30FF` | Red, medium stroke |
| Highlighter | `tool.highlighter` | `#FFD60A66` | Yellow, low alpha |
| Arrow | `tool.arrow` | `#0A84FFFF` | Blue, medium stroke |
| Rectangle | `tool.rectangle` | `#34C759FF` | Green, medium stroke |
| Ellipse | `tool.ellipse` | `#AF52DEFF` | Purple, medium stroke |
| Text | `tool.text` | `#FFFFFFFF` | White text |
| Eraser | `tool.eraser` | `N/A` | Removes selected object |

Default stroke widths:
- Pen: 4 px
- Highlighter: 12 px
- Arrow/Rectangle/Ellipse: 4 px
- Text: 24 px font

## 5.3 Default Shortcut Map (macOS)
Use a two-tier strategy:
- Tier 1: one command chord to enter/exit annotate mode.
- Tier 2: quick tool switches while annotate mode is active.

Proposed defaults:

| Command | Shortcut |
|---|---|
| Toggle Annotation Mode | `Control + Option + A` |
| Start/Stop Recording | `Control + Option + R` |
| Pause/Resume Recording | `Control + Option + P` |
| Tool: Pen | `Control + Option + 1` |
| Tool: Highlighter | `Control + Option + 2` |
| Tool: Arrow | `Control + Option + 3` |
| Tool: Rectangle | `Control + Option + 4` |
| Tool: Ellipse | `Control + Option + 5` |
| Tool: Text | `Control + Option + 6` |
| Tool: Eraser | `Control + Option + E` |
| Undo | `Control + Option + Z` |
| Redo | `Control + Option + Shift + Z` |
| Clear All | `Control + Option + Backspace` |
| Cycle Colors | `Control + Option + C` |
| Increase Stroke | `Control + Option + ]` |
| Decrease Stroke | `Control + Option + [` |
| Toggle Radial Control | `Control + Option + Space` |

Implementation note:
- Keep all shortcuts user-configurable in Settings.
- Validate conflicts and reserve fallback defaults.

## 5.4 Tool Options Matrix

| Tool Group | Options | Modifier Behavior |
|---|---|---|
| `Circle`, `Rectangle`, `Highlighter`, `Pencil` | line thickness, color, line style (`solid`, `dotted`, `hyphen`) | Holding `Shift` constrains drawing: circle/ellipse -> perfect circle, rectangle -> square, pencil/highlighter -> straight line |
| `Arrow` | single-sided/double-sided, color, line style (`solid`, `dotted`, `hyphen`) | Holding `Shift` draws straight arrows |
| `Text` | font, color, size, background color (if supported), border style (if supported) | No additional modifier required |
| Other tools | no options panel | N/A |

Persistence rule:
- If user has previously saved options for a tool, those are reused.
- Otherwise, tool defaults from section `5.2` apply.

## 6. Core Data Contracts

```swift
enum SessionMode {
    case idle
    case annotating
    case recording
    case recordingAndAnnotating
    case paused
}

enum ToolKind: String, Codable {
    case pen, highlighter, arrow, rectangle, ellipse, text, eraser
}

struct ToolConfig: Codable {
    var colorHexRGBA: String
    var strokeWidth: Double
    var opacity: Double
}

struct ShortcutBinding: Codable {
    var commandID: String
    var keyCode: UInt16
    var modifiers: UInt
}
```

## 7. Event Flows

### 7.1 Toggle Annotation
1. Global shortcut triggers `CommandID.toggleAnnotation`.
2. Session orchestrator transitions `idle -> annotating` or reverse.
3. Overlay windows are created/destroyed per display.
4. Current tool HUD is shown/hidden.

### 7.2 Start Recording
1. User command from shortcut or menu.
2. Permission check for Screen Recording.
3. Recording engine starts stream + writer.
4. Session state transitions:
   - `idle -> recording`
   - `annotating -> recordingAndAnnotating`

### 7.3 Draw Stroke
1. Pointer down/move/up captured by overlay.
2. Active `ToolRenderer` builds vector element.
3. Element committed to overlay scene graph.
4. Undo stack updated.

### 7.4 Stop Recording
1. Command triggers writer finalization.
2. File storage returns output URL.
3. Optional local notification with “Reveal in Finder”.
4. Session returns to `idle` or `annotating` depending on prior mode.

### 7.5 Use Radial On-Screen Control
1. User toggles radial control via shortcut or menu command.
2. Overlay shows collapsed single-circle control at last saved position.
3. Hovering the center circle activates control and expands the first donut ring of tools.
4. User clicks a tool to select it.
5. Selection dispatches command updates to `AppStore` and active overlay renderer/command stack.
6. If the selected tool supports options, user opens options via the center options-trigger icon.
7. Options panel appears below the first ring and moves with the radial control.
8. User confirms changes with `OK` or discards with `Cancel`.
9. When focus is lost, a 3-second inactivity timer starts.
10. If no new interaction occurs before timeout, control deactivates and collapses to the single-circle state.

### 7.6 Hover First-Ring Tool For Name Tooltip
1. User hovers a tool in the first donut ring.
2. Tooltip appears near pointer with tool name.
3. Tooltip hides when pointer leaves the tool target.

### 7.7 Open Tool Options Panel
1. User selects a tool in the first ring.
2. Center `X` is replaced by options-trigger icon (color-picker icon).
3. User clicks options-trigger icon.
4. Tool-specific options panel appears below the first ring, anchored to the control.
5. User edits options and chooses `OK` or `Cancel`.
6. `OK` applies and persists tool settings; `Cancel` discards edits.
7. Panel closes and center icon returns to `X`.

## 8. Rendering Strategy
- Store annotations as vector objects (`ShapeElement`, `TextElement`, `ArrowElement`).
- Render through `CAShapeLayer`/`CATextLayer` for low-latency updates.
- Keep SwiftUI for controls; use AppKit/Core Animation for overlay rendering performance.

## 9. Reliability and Performance Targets
- Annotation latency: < 16 ms target on Apple Silicon.
- Recording stability: no dropped session under 1080p@30 for 30 min baseline.
- Startup (menu bar ready): < 1.5s cold launch.
- Crash-safe recording finalization on stop.

## 10. Security and Privacy
- Capture only selected display(s).
- Store recordings locally by default.
- No outbound networking in v1.
- Provide clear “recording active” indicator in menu bar and overlay HUD.

## 11. AI Agent Implementation Plan

This section is the executable roadmap. The implementing AI agent must complete phases in order, then update phase status and decision notes after each phase.
The concrete, task-level execution board is `docs/IMPLEMENTATION_TASKS.md` and must be kept current during implementation.

### 11.1 Phase Checklist
- [x] Phase 0: Project scaffolding and protocols
- [x] Phase 1: Menu bar app shell and state store
- [x] Phase 2: Global shortcuts
- [ ] Phase 3: Overlay engine (single display)
- [x] Phase 4: Tool renderers + undo/redo
- [x] Phase 5: Multi-display support
- [ ] Phase 6: Recording engine integration
- [ ] Phase 7: Settings UI for shortcuts/colors
- [ ] Phase 8: Persistence and output management
- [ ] Phase 9: Stabilization, profiling, test pass

Tracking rule:
- Use `docs/IMPLEMENTATION_TASKS.md` for day-to-day status updates.
- Keep exactly one task marked `in_progress` at any given time.

### 11.2 Detailed Phases

#### Phase 0: Project scaffolding and protocols
Deliverables:
- Create folder structure for `App`, `Domain`, `Services`, `Overlay`, `Recording`, `Settings`.
- Define service protocols:
  - `ShortcutService`
  - `OverlayService`
  - `RecordingService`
  - `PermissionService`
  - `PreferencesService`
- Add basic dependency injection container.

Update required:
- Mark phase complete in this document.
- Add `Phase 0` notes under Decision Log.

#### Phase 1: Menu bar app shell and state store
Deliverables:
- Add `MenuBarExtra` with core controls.
- Add `AppStore` and session mode transitions.
- Add command dispatch mechanism (`CommandID`).

Update required:
- Mark phase complete.
- Document any state model changes.

#### Phase 2: Global shortcuts
Deliverables:
- Register defaults from section 5.3.
- Map shortcuts to commands.
- Conflict detection and fallback behavior.

Update required:
- Mark phase complete.
- Document any shortcut changes from defaults.

#### Phase 3: Overlay engine (single display)
Deliverables:
- Create transparent top-level overlay window.
- Enable pointer capture in annotate mode.
- Draw basic pen tool path with low latency.

Update required:
- Mark phase complete.
- Record performance numbers for draw latency.

#### Phase 4: Tool renderers + undo/redo
Deliverables:
- Implement highlighter, arrow, rectangle, ellipse, text, eraser.
- Add command stack for undo/redo.
- Add clear-all command.

Update required:
- Mark phase complete.
- Document renderer data model adjustments.

#### Phase 5: Display selection and layout support
Deliverables:
- Select the session display from the current mouse location when annotation starts.
- Correct coordinate transformation between displays.
- Keep overlay and pass-through UI confined to the chosen display for the session.

Update required:
- Mark phase complete.
- Add notes on coordinate edge cases handled.

#### Phase 6: Recording engine integration
Deliverables:
- Integrate `ScreenCaptureKit`.
- Start/stop/pause recording commands.
- Save recording file and expose reveal action.

Update required:
- Mark phase complete.
- Log encode settings and known limitations.

#### Phase 7: Settings UI for shortcuts/colors
Deliverables:
- Shortcut editor UI.
- Tool color/stroke editor UI.
- Permission status and re-check actions.

Update required:
- Mark phase complete.
- Document final default palette and keymap changes.

#### Phase 8: Persistence and output management
Deliverables:
- Persist preferences in `UserDefaults`.
- Validate output directory and file naming policy.
- Add basic metadata sidecar (optional JSON).

Update required:
- Mark phase complete.
- Note migration handling for preference schema changes.

#### Phase 9: Stabilization, profiling, test pass
Deliverables:
- Unit tests for state transitions and command routing.
- Manual test matrix for permissions, displays, and recording lifecycle.
- Performance baseline report.

Update required:
- Mark phase complete.
- Add final release readiness summary.

### 11.3 Professional Code Quality Gates (Mandatory)
Every implementation phase must satisfy all gates below before being marked complete.

- `Design gate`: Changes preserve module boundaries (UI, Domain, Services, Engines) and avoid leaking infrastructure concerns into SwiftUI views.
- `Correctness gate`: New behavior is covered by focused tests or, when automated tests are impractical, a documented manual verification matrix.
- `Safety gate`: Error paths are handled explicitly with recoverable flows and clear user feedback for permission, recording, and file-write failures.
- `Concurrency gate`: UI-facing state mutations are on the main actor; background capture/encoding work is isolated to non-UI threads.
- `Performance gate`: No regressions against section `9` targets for annotation latency, startup time, and recording stability.
- `Observability gate`: Add logs for lifecycle-critical transitions (start/stop/pause recording, permission denial, overlay activation).
- `Review gate`: Each phase update in section `13` must include what was validated (build/tests/manual checks) and known limitations.

## 12. Definition of Done (v1)
- Menu bar app launches and manages annotation/recording lifecycle.
- All default tools function with keyboard switching.
- Recording files are produced reliably and saved in configured location.
- Shortcuts and colors are configurable and persisted.
- Permissions are handled with clear user guidance.
- Optional radial on-screen control is usable, non-blocking, and configurable.
- Hovering first-ring tools shows accurate tool-name tooltips.
- Radial control supports keyboard-light workflow for tool/color/stroke and quick actions.
- Per-tool options panel (below first ring) supports `OK`/`Cancel` and persistent per-tool settings.
- All phase quality gates in section `11.3` are satisfied and documented.

## 13. Decision Log (Agent Must Update)

| Date | Phase | Decision | Reason | Impact |
|---|---|---|---|---|
| YYYY-MM-DD | N | TBD | TBD | TBD |
| 2026-03-31 | 0 | Introduced protocol-first service layer with `AppContainer` composition root and no-op/in-memory bootstrap implementations | Establishes strict module boundaries early while keeping Phase 0 startup stable and testable | Enables future phase services to swap concrete implementations without changing UI/domain contracts; adds runnable smoke-test target baseline |
| 2026-03-31 | 0 | Updated protocol isolation contracts and preference serialization rules; reordered section 4 headings sequentially | Addresses concrete review findings for concurrency correctness, persistence safety, and document navigability | Prevents actor isolation leaks and non-codable preference writes; improves test signal quality and architecture readability |
| 2026-04-01 | 3/4 | Re-scoped radial interaction to hover-activation and 3-second focus-loss timeout; replaced shared second ring with per-tool options panel below first ring | Existing interaction model produced redundant second ring behavior and did not match desired UX | Prioritizes a new corrective batch in Phase 3/4 before continuing to Phase 6+ |
| 2026-04-01 | 3/4 | Implemented full corrective batch: hover→activate (3s collapse), no secondary ring, center-icon swap (paintpalette for configurable tools), ToolOptionsPanelView anchored below first ring with OK/Cancel, LineStyle/ArrowStyle/TextFontDesign domain enums, ToolExtendedOptions in ToolState, per-element line style and arrow style stored in OverlaySceneElement.Kind, double-headed arrow renderer, font design per text element, applyToolOptions OverlayAction round-tripped through AppStore | P3-T13/T07/T14/T15/T16/T17 and P4-T08/T09/T10/T11 all done; static review and new targeted tests cover model correctness, options routing, and scene undo/redo; xcodebuild unavailable (CommandLineTools); P3-T09 remains blocked on manual GUI checklist |
| 2026-04-01 | 3/4 | Removed 3-second radial auto-collapse timer (HUD stays expanded permanently); added Escape key with multi-level handler (cancel options → cancel text → deselect tool + enter pass-through mode); introduced `PassThroughContainerView` with per-area `hitTest` override so mouse events reach underlying apps in pass-through mode while HUD/radial remain interactive; added red `×` close button on options panel as Cancel alias; fixed text-element config snapshot in `beginTextEditing` so in-progress text color/font/size are frozen at edit-start and unaffected by later tool-config changes; replaced system `.help()` tooltips with custom `@State hoveredItem` overlay labels for reliable display in non-activating panels; app is activated and overlay panel made key on annotation start to enable local key event monitoring | Closing batch of P3/P4 UX fixes required before Phase 6; xcodebuild unavailable (CommandLineTools) | Sections 4.8 and 4.9 updated to reflect permanent-HUD and pass-through contracts; P3-T09 manual checklist still open |
| 2026-04-01 | 3 | Added an eraser-specific overlay cursor and Shift-constrained drawing behavior; pen/highlighter now commit a straight two-point stroke while arrows snap to 45° increments from drag origin | Final Phase 3 usability polish requested for active annotation mode, while preserving existing pass-through behavior and scene model contracts | Improves drawing precision and tool affordance immediately; Phase 3 still awaits manual GUI checklist validation in a full macOS runtime |
| 2026-04-01 | 3 | Extended Phase 3 modifier behavior so Shift previews and commits constrained square/circle shapes, made pass-through center-tap return directly to annotation even with no selected tool, and changed text placement to a left-aligned anchored origin | Follows the same overlay interaction contract while closing obvious gaps in modifier consistency and text placement ergonomics | Keeps all constrained tools preview-first during drag and makes text placement feel predictable; manual GUI validation is still required before Phase 3 can be closed |
| 2026-04-01 | 3 | Enriched tooltips with per-tool `Shift` modifier hints and moved the initial radial/HUD spawn point to the right side of the overlay on first appearance | Makes the modifier affordances discoverable in-place and aligns the initial overlay chrome placement with the requested startup position | Reduces guesswork for constrained drawing and avoids having the radial start on the left unless the user later repositions it manually |
| 2026-03-31 | 1 | Added `MenuBarExtra` app shell, introduced `AppStore` with `SessionMode`/`ToolState`, and centralized command dispatch via `CommandID` reducer for annotation and recording lifecycle | Establishes a deterministic, testable state transition core for UI and service orchestration while exposing real-time active-mode status in the menu bar | Completes Phase 1 deliverables and provides a stable base for Phase 2 shortcut routing; validation: transition tests added, but `xcodebuild` execution is currently blocked in this environment because full Xcode is not configured |
| 2026-03-31 | 2 | Added a codable shortcut model/default keymap, conflict fallback validator, and `AppKitShortcutService` for local/global key event routing; wired shortcut registration and persisted bindings through `AppStore` | Delivers Phase 2 global shortcut routing with deterministic command mapping and a safe fallback when user bindings conflict | Completes Phase 2 deliverables and enables shortcut-driven lifecycle/tool selection; validation: new shortcut tests added but `xcodebuild` execution remains blocked in this environment (active developer directory is CommandLineTools), known limitation: undo/redo/clear/color/stroke/radial command handlers are currently intentional no-ops until later phases |
| 2026-03-31 | 3 | Implemented single-display AppKit overlay engine with transparent top-level panel, pointer-driven pen/highlighter vector strokes, active-tool HUD, and radial control (collapsed/expanded/secondary rings, shortcut tooltips, focus-loss timeout collapse) wired through `OverlayService` and `AppStore` command dispatch | Delivers the core Phase 3 runtime interaction loop while preserving module boundaries (`AppStore` <-> `OverlayService`) and enabling later undo/redo integration without UI rewrites | Phase 3 remains in progress: P3-T01..P3-T08 and P3-T11..P3-T14 are implemented; P3-T09 remains blocked on manual GUI checklist. P3-T10 was completed in Phase 4 after undo/redo/clear integration. Validation: added overlay wiring smoke tests; `xcodebuild` could not run in this environment because active developer directory is CommandLineTools |
| 2026-03-31 | 4 | Introduced a unified overlay scene-element model with shape/text renderers, eraser hit-removal, and undo/redo/clear command stack; wired `AppStore` commands to concrete overlay operations | Completes Phase 4 deliverables while preserving Phase 3 overlay/radial UI and keeping command orchestration in `AppStore` with rendering state isolated to the overlay engine | Phase 4 is complete and P3-T10 quick actions are now active through dispatcher -> overlay command execution. Validation: added mixed-history scene model tests and AppStore-to-overlay command routing tests; `xcodebuild` still cannot run in this environment because active developer directory is CommandLineTools. Known limitation: clear-all confirmation UX remains a follow-up UI behavior for later settings/polish phases. |
| 2026-03-31 | 5 | Reworked overlay runtime to track displays dynamically, render one panel per active display, and use a shared global-space scene model with explicit `DisplayCoordinateTransformer` conversions for per-screen rendering and input; tightened radial task cancellation handling and moved screen observer teardown out of deinit | Delivers Phase 5 multi-display behavior while preserving service boundaries and fixing edge cases for negative-origin displays, mixed-scale layouts, and arrowhead clipping near display boundaries | Phase 5 is complete (`P5-T01..P5-T05` done). Validation: added coordinate conversion tests (negative-origin + mixed-scale cases) and static verification of multi-panel synchronization; `xcodebuild` remains unavailable in this environment because active developer directory is CommandLineTools. Residual risk: attach/detach behavior still requires manual GUI verification in full macOS runtime. |
| 2026-03-31 | 2 | Repaired `ServiceProtocols.swift` shortcut mapping extension syntax by closing `ShortcutKey` extension after the Carbon key-code switch | Restores compile-time correctness for the AppKit global-hotkey adapter path and removes parser desynchronization that surfaced as C function pointer diagnostics | Validation: `swiftc -frontend -parse Pinnacle/Services/ServiceProtocols.swift` passes. Full project build is still blocked in this environment because `xcodebuild` requires full Xcode (active developer directory is CommandLineTools). |
| 2026-04-01 | 3 | Refined pass-through center-button recovery so the center tap reselects the active tool workflow exactly like a tool tap, and reduced default stroke widths for pen/arrow/rectangle/ellipse to `1` while keeping the highlighter broader | Keeps pass-through exit behavior consistent with the radial tool-selection contract and makes thin-outline drawing the default for non-highlighter tools without changing text sizing semantics | Validation: `swiftc -frontend -parse Pinnacle/Domain/AppDomainModels.swift Pinnacle/Overlay/OverlayViewModel.swift PinnacleTests/PinnacleSmokeTests.swift` passes; `xcodebuild` remains unavailable in this environment because `xcode-select` points to CommandLineTools. Residual risk: the final Phase 3 GUI checklist still needs a full macOS/Xcode runtime. |
| 2026-04-01 | 3 | Removed the relocation drag gesture from the non-relocatable pass-through center control so the center tap is handled on the first click instead of being pre-empted by a zero-distance drag recognizer | Preserves draggable radial behavior in normal annotation mode while making the pass-through overlay’s center-button interaction deterministic and immediate | Validation: `swiftc -frontend -parse Pinnacle/Overlay/RadialControlView.swift Pinnacle/Overlay/OverlayViewModel.swift` passes; `xcodebuild` remains unavailable in this environment because `xcode-select` points to CommandLineTools. Residual risk: the final Phase 3 GUI checklist still needs a full macOS/Xcode runtime. |
| 2026-04-01 | 3 | Corrected the pass-through center-button contract so the first click only exits pass-through without preselecting any tool, and derived the pass-through panel’s local radial center from the clamped frame so the visible HUD position remains stable near display edges | Aligns pass-through exit behavior with the user expectation of “resume annotation, then choose a tool explicitly” while preserving spatial continuity between the pass-through panel and the full overlay radial control | Validation: `swiftc -frontend -parse Pinnacle/Overlay/OverlayViewModel.swift Pinnacle/Overlay/AppKitOverlayService.swift PinnacleTests/PinnacleSmokeTests.swift` passes; `xcodebuild` remains unavailable in this environment because `xcode-select` points to CommandLineTools. Residual risk: the final Phase 3 GUI checklist still needs a full macOS/Xcode runtime. |
| 2026-04-01 | 3 | Refreshed multi-display targeting so pass-through entry/exit derives `activeDisplayID` from the current mouse display and overlay mouse events keep that display in sync, preventing the first exit click from flashing the overlay onto a stale secondary monitor | Keeps the single-active-display overlay contract coherent across pass-through transitions by making display focus follow the actual interaction point rather than the display captured at overlay startup. This behavior is superseded by the later single-session-display decision below. | Validation: `swiftc -frontend -parse Pinnacle/Overlay/AppKitOverlayService.swift Pinnacle/Overlay/OverlayViewModel.swift` passes; `xcodebuild` remains unavailable in this environment because `xcode-select` points to CommandLineTools. Residual risk: the final Phase 3 GUI checklist still needs a full macOS/Xcode runtime. |
| 2026-04-01 | 5 | Re-scoped display behavior so annotation sessions bind to exactly one display chosen from the current mouse location at action start; only that display gets overlay and pass-through panels for the life of the session | Matches the requested product behavior of “use one monitor only” while preserving the coordinate-transform and display-lifecycle groundwork for future recording/display selection work | Validation: `swiftc -frontend -parse Pinnacle/Overlay/AppKitOverlayService.swift Pinnacle/Overlay/OverlayViewModel.swift` passes; `xcodebuild` remains unavailable in this environment because `xcode-select` points to CommandLineTools. Residual risk: manual GUI validation is still required for far-edge placement and monitor attach/detach during an active session. |
| 2026-04-02 | 4 | Updated the default annotation presets so text and highlighter sizes start at `14`, pen/highlighter/text default to yellow, arrow/rectangle/ellipse default to blue, and the eraser cursor glyph renders red | Aligns the initial tool behavior with the newly requested visual defaults while keeping existing per-tool option flows and cursor hotspot behavior unchanged | Validation: `swiftc -frontend -parse Pinnacle/Domain/AppDomainModels.swift Pinnacle/Overlay/OverlayViewModel.swift Pinnacle/Overlay/OverlayPanel.swift PinnacleTests/PinnacleSmokeTests.swift` passes; `xcodebuild test -project Pinnacle.xcodeproj -scheme Pinnacle -destination 'platform=macOS' -derivedDataPath /tmp/PinnacleDerivedData -only-testing:PinnacleTests/PinnacleSmokeTests CODE_SIGNING_ALLOWED=NO` cannot run here because `xcode-select` points to CommandLineTools. |
| 2026-04-02 | 4 | Replaced the broken tinted-SF-Symbol eraser cursor with dedicated custom artwork and added an explicit overlay activation hook so keyboard tool shortcuts reuse the same radial-selection path as mouse clicks, including exiting pass-through mode | The symbol-based cursor did not render reliably as a red eraser in practice, and shortcut-driven tool selection needed to resume annotation mode with the same UI state transition users get from clicking a radial tool | Validation: `swiftc -frontend -parse Pinnacle/Services/ServiceProtocols.swift Pinnacle/Services/StubServices.swift Pinnacle/App/AppStore.swift Pinnacle/Overlay/OverlayViewModel.swift Pinnacle/Overlay/AppKitOverlayService.swift Pinnacle/Overlay/OverlayPanel.swift PinnacleTests/PinnacleSmokeTests.swift` passes; `xcodebuild` remains unavailable here because `xcode-select` points to CommandLineTools. |
| 2026-04-02 | 4 | Stabilized the text-tool edit handoff by assigning each `TextDraft` a unique identity, deferring replacement draft creation until the next main-loop turn after commit, and explicitly dismantling the previous `NSTextField` editor/responder when SwiftUI removes it | Clicking a second text location while editing was functionally creating the next draft, but AppKit input analytics and ViewBridge warnings indicated the previous field was being torn down mid-session without a clean responder shutdown | Validation: `swiftc -frontend -parse Pinnacle/Overlay/OverlayScene.swift Pinnacle/Overlay/OverlayViewModel.swift Pinnacle/Overlay/OverlayRootView.swift PinnacleTests/PinnacleSmokeTests.swift` passes; `xcodebuild` remains unavailable here because `xcode-select` points to CommandLineTools. |

## 14. Risks and Mitigations
- Global hotkey API edge cases:
  - Mitigation: encapsulate provider behind `ShortcutService`.
- Overlay performance degradation on complex scenes:
  - Mitigation: layer pooling and scene element culling.
- Recording permission confusion:
  - Mitigation: explicit settings screen guidance with retry checks.
- Multi-display coordinate bugs:
  - Mitigation: centralized coordinate conversion utility + dedicated tests.
