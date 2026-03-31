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
- `RadialControlOverlay` (optional but recommended): compact center circle that expands to an outer donut of tools, with secondary donut options per selected tool.

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
- Clicking the center circle activates control.
- Activated control expands tool actions into an outer donut ring around the center circle.
- Clicking a tool expands a secondary donut ring with options for that tool.
- Control deactivates 5 seconds after losing focus (pointer leaves control and no interaction continues).
- On deactivation, control collapses back to the single small circle.
- Draggable with edge snap and remembers last position.
- Pass-through interaction outside control bounds.
- Hovering an actionable item shows tooltip with command label and current key binding.

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
- Creates one transparent overlay window per active display.
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
3. Clicking the circle activates control and expands an outer donut of tools.
4. Clicking a tool expands a second donut with tool-specific options.
5. User picks tool/color/stroke or quick action (undo/redo/clear) from first or second donut.
6. Selection dispatches command updates to `AppStore` and active overlay renderer/command stack.
7. When focus is lost, a 5-second inactivity timer starts.
8. If no new interaction occurs before timeout, control deactivates and collapses to the single-circle state.

### 7.6 Hover HUD/Radial Item For Shortcut Tooltip
1. User hovers a HUD or radial item.
2. Overlay resolves mapped command and current shortcut binding.
3. Tooltip appears near pointer with command label and key binding (example: `Pen (Ctrl+Opt+1)`).
4. Tooltip hides on pointer leave or action execution.
5. Tooltip content refreshes immediately after shortcut remap changes.

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
- [ ] Phase 0: Project scaffolding and protocols
- [ ] Phase 1: Menu bar app shell and state store
- [ ] Phase 2: Global shortcuts
- [ ] Phase 3: Overlay engine (single display)
- [ ] Phase 4: Tool renderers + undo/redo
- [ ] Phase 5: Multi-display support
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

#### Phase 5: Multi-display support
Deliverables:
- Overlay per active display.
- Correct coordinate transformation between displays.
- Tool behavior parity across screens.

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
- Hovering HUD/radial controls shows accurate key binding tooltips.
- Radial control supports keyboard-light workflow for tool/color/stroke and quick actions.
- All phase quality gates in section `11.3` are satisfied and documented.

## 13. Decision Log (Agent Must Update)

| Date | Phase | Decision | Reason | Impact |
|---|---|---|---|---|
| YYYY-MM-DD | N | TBD | TBD | TBD |

## 14. Risks and Mitigations
- Global hotkey API edge cases:
  - Mitigation: encapsulate provider behind `ShortcutService`.
- Overlay performance degradation on complex scenes:
  - Mitigation: layer pooling and scene element culling.
- Recording permission confusion:
  - Mitigation: explicit settings screen guidance with retry checks.
- Multi-display coordinate bugs:
  - Mitigation: centralized coordinate conversion utility + dedicated tests.
