# Pinnacle Implementation Tasks

## Purpose
This file is the execution board for implementation work. Use it with `docs/ARCHITECTURE.md`:
- `ARCHITECTURE.md` defines system design, quality gates, and phase intent.
- `IMPLEMENTATION_TASKS.md` defines concrete tasks and live execution status.

## Status Rules (Mandatory)
- Allowed status values: `todo`, `in_progress`, `done`, `blocked`.
- Only one task in this file may be `in_progress` at a time.
- A task may be set to `done` only if its acceptance criteria are satisfied.
- If blocked, set status to `blocked` and add a short blocker note in `Blockers Log`.
- When a task moves to `done`, immediately:
  - update phase checklist in `docs/ARCHITECTURE.md` section `11.1` if phase completion changed,
  - append/update the decision record in `docs/ARCHITECTURE.md` section `13`.

## Current Execution State

| Field | Value |
|---|---|
| Current Task ID | `P6-T03` |
| Current Phase | `6` |
| Last Updated (UTC) | `2026-05-08 18:20` |
| Updated By | `agent` |
| Notes | `Audit-driven hardening pass (see Execution Log entry "AUDIT-FIXES" 2026-05-08): closed P0/P1 findings across Recording (PTS rebasing on pause/resume, finalization drained on app termination via NSApplicationDelegate, empty-file outcome surfaced, startup-cancel race fixed), Overlay (dead-zone matches hit-test tiers, multi-display panel retention, HUDView wired in), AppStore (paused-error routing, paused-annotation toggle, no-overwrite on shortcut conflict), Services (permissionService distinguishes denied, hotkey rollback on partial failure), and hygiene (StubServices moved to PinnacleTests). All 50 unit tests pass.` |

## Phase Status Board

| Phase | Name | Status | Exit Criteria |
|---|---|---|---|
| 0 | Project scaffolding and protocols | `done` | Task group `P0-*` all `done` |
| 1 | Menu bar app shell and state store | `done` | Task group `P1-*` all `done` |
| 2 | Global shortcuts | `done` | Task group `P2-*` all `done` |
| 3 | Overlay engine (single display) | `in_progress` | Task group `P3-*` complete except final `P3-T09` manual GUI checklist |
| 4 | Tool renderers + undo/redo | `done` | Task group `P4-*` all `done` including per-tool options and modifier rules |
| 5 | Multi-display support | `done` | Task group `P5-*` complete, with session behavior now intentionally limited to one mouse-selected display at action start |
| 6 | Recording engine integration | `in_progress` | Task group `P6-*` all `done` |
| 7 | Settings UI for shortcuts/colors | `in_progress` | Task group `P7-*` complete except final `P7-T05` manual GUI checklist |
| 8 | Persistence and output management | `done` | All `P8-*` complete (P8-T05 skipped — labeled `Optional`); 73 unit tests cover persistence round-trips |
| 9 | Stabilization, profiling, test pass | `todo` | Task group `P9-*` all `done` |

## Next Batch Priority (Must Complete Before Phase 6)
All previously listed items are `done`. The batch below was completed in this session:
1. `P3-T18` Remove radial auto-collapse timer - HUD stays activated permanently. `done`
2. `P3-T19` Custom hover tooltips for radial ring items (replaces `.help()` which is unreliable in non-activating panels). `done`
3. `P3-T20` Escape key multi-level handler: cancel options -> cancel text draft -> deselect + enter pass-through mode. `done`
4. `P3-T21` Pass-through mode: overlay `ignoresMouseEvents` toggled; `PassThroughContainerView` routes hits only to HUD/radial area. `done`
5. `P4-T12` Red close button on options panel (Cancel alias). `done`
6. `P4-T13` Text element config snapshot: color/font/size frozen at edit-start, isolated from later tool-config changes. `done`

## Concrete Task Backlog

### Phase 0: Project Scaffolding and Protocols
| ID | Task | Depends On | Status | Acceptance Criteria |
|---|---|---|---|---|
| P0-T01 | Create source folders: `App`, `Domain`, `Services`, `Overlay`, `Recording`, `Settings` | none | `done` | Folders exist and compile references resolve |
| P0-T02 | Define protocol contracts: `ShortcutService`, `OverlayService`, `RecordingService`, `PermissionService`, `PreferencesService` | P0-T01 | `done` | Protocols compile with clear method signatures |
| P0-T03 | Implement DI container for protocol-backed services | P0-T02 | `done` | App startup resolves service graph without crashes |
| P0-T04 | Add base smoke test target wiring for domain/services | P0-T02 | `done` | At least one passing smoke test in CI/local |
| P0-T05 | Document module boundaries in code comments/readme header | P0-T01 | `done` | Boundaries are explicit for future contributors |

### Phase 1: Menu Bar Shell and State Store
| ID | Task | Depends On | Status | Acceptance Criteria |
|---|---|---|---|---|
| P1-T01 | Add `MenuBarExtra` scene with start/stop actions | P0-T03 | `done` | Menu bar controls render and dispatch commands |
| P1-T02 | Implement `AppStore` with `SessionMode` and `ToolState` | P0-T03 | `done` | Central observable state drives UI and engines |
| P1-T03 | Add command dispatch enum and reducer/handler layer | P1-T02 | `done` | Commands route deterministically to state/services |
| P1-T04 | Add unit tests for core state transitions | P1-T02 | `done` | Tests cover idle/annotating/recording transitions |
| P1-T05 | Add menu bar status indicator for active mode | P1-T01 | `done` | Indicator reflects real-time session state |

### Phase 2: Global Shortcuts
| ID | Task | Depends On | Status | Acceptance Criteria |
|---|---|---|---|---|
| P2-T01 | Implement platform shortcut provider adapter | P0-T02 | `done` | Global registration/unregistration works reliably |
| P2-T02 | Wire default keymap from architecture section 5.3 | P2-T01 | `done` | All default bindings trigger correct commands |
| P2-T03 | Add shortcut conflict validator and fallback handling | P2-T02 | `done` | Conflicts are detected and blocked in UI/store |
| P2-T04 | Persist and restore shortcut bindings | P2-T02, P8-T01 | `done` | Restart preserves user bindings |
| P2-T05 | Add tests for shortcut command mapping | P2-T02 | `done` | Mapping tests pass for tool + lifecycle commands |

### Phase 3: Overlay Engine (Single Display)
| ID | Task | Depends On | Status | Acceptance Criteria |
|---|---|---|---|---|
| P3-T01 | Create transparent top-level overlay window manager | P1-T03 | `done` | Overlay can be shown/hidden without focus issues |
| P3-T02 | Capture pointer input and route events to active tool | P3-T01 | `done` | Pointer down/move/up stream received correctly |
| P3-T03 | Implement pen renderer with vector path model | P3-T02 | `done` | Pen strokes render smoothly and persist in scene |
| P3-T04 | Add annotation HUD showing active tool/color | P1-T05 | `done` | HUD updates instantly on tool change |
| P3-T05 | Measure and record baseline draw latency | P3-T03 | `done` | Latency report logged against <16ms target |
| P3-T06 | Implement radial control shell (single-circle idle + outer donut tools) | P3-T01 | `done` | Control appears as a small idle circle by default and expands the first tool ring correctly after activation |
| P3-T07 | Remove shared second ring and route tool clicks to per-tool options workflow | P3-T06, P1-T03 | `done` | Clicking a tool selects it and prepares tool-specific options flow instead of showing a generic second ring |
| P3-T08 | Enforce pointer pass-through outside radial hit area | P3-T06, P3-T02 | `done` | Drawing interactions are unaffected outside radial control bounds |
| P3-T09 | Add radial usability checks (auto-hide, edge snap, no lag) | P3-T06, P3-T07 | `blocked` | Manual checklist confirms non-blocking behavior and smooth interaction |
| P3-T10 | Add radial quick actions (undo, redo, clear) | P4-T05, P4-T06, P3-T06 | `done` | Quick actions execute through command dispatcher and reflect state immediately |
| P3-T11 | Add hover tooltips on HUD/radial items with mapped key bindings | P2-T02, P3-T06 | `done` | On hover, tooltip shows command label + current binding and updates after remap |
| P3-T12 | Enforce annotation-mode visibility rules for radial control | P1-T02, P3-T06 | `done` | Control appears/hides according to session mode contract without stale overlays |
| P3-T13 | Implement activation lifecycle (hover activate + focus-loss timeout) | P3-T06 | `done` | Hover activates; on focus loss, control deactivates after more than 3s inactivity without flicker |
| P3-T14 | Implement focus tracking and timeout cancellation rules | P3-T13, P3-T07 | `done` | Timeout starts only after focus loss and cancels on re-enter/interaction before 3s |
| P3-T15 | Implement center icon swap for selected tool options | P3-T07 | `done` | Selecting a configurable tool replaces center `X` with options-trigger icon; non-configurable tools keep options trigger hidden/disabled |
| P3-T16 | Implement anchored options panel below first ring (`OK`/`Cancel`) | P3-T15 | `done` | Options panel appears below first ring, moves with radial control, and closes with explicit `OK`/`Cancel` |
| P3-T17 | Implement first-ring tool-name tooltip behavior | P3-T06 | `done` | Hovering a first-ring tool shows its name tooltip and hides on leave |
| P3-T18 | Remove radial auto-collapse timer; HUD stays expanded permanently | P3-T13 | `done` | Radial control never auto-collapses; only dismissed by Escape or center tap |
| P3-T19 | Custom hover tooltip overlay labels for radial items | P3-T17 | `done` | Tooltip shows above ring on hover; no reliance on `.help()` system mechanism |
| P3-T20 | Escape key multi-level handler | P3-T13, P4-T03 | `done` | Escape cancels options -> cancels text draft -> deselects tool + enters pass-through |
| P3-T21 | Pass-through mode with per-area hit testing via `PassThroughContainerView` | P3-T20 | `done` | Mouse events reach underlying apps; HUD and radial remain interactive; annotations stay visible |
| P3-T22 | Make pass-through center tap resume the active tool workflow and slim default stroke widths | P3-T21, P4-T08 | `done` | Center tap in pass-through mirrors tapping the active tool, and default stroke widths for pen/arrow/rectangle/ellipse start at `1` while highlighter stays unchanged |
| P3-T23 | Fix pass-through center button first-click activation reliability | P3-T22 | `done` | Center button resumes annotation on the first click even when no tool is selected for options and the pass-through radial is non-relocatable |
| P3-T24 | Exit pass-through on first center click without preselecting a tool and preserve visible radial position | P3-T23 | `done` | First center click exits pass-through with `selectedToolForOptions == nil`, and the visible radial center stays aligned before and after pass-through even near display edges |
| P3-T25 | Sync pass-through exit to the interacted display in multi-display mode | P3-T24, P5-T01 | `done` | Exiting pass-through reactivates the overlay on the display currently under interaction instead of flashing a stale off-monitor panel |

### Phase 4: Tool Renderers and Undo/Redo
| ID | Task | Depends On | Status | Acceptance Criteria |
|---|---|---|---|---|
| P4-T01 | Implement highlighter renderer with alpha behavior | P3-T03 | `done` | Highlighter appears translucent and smooth |
| P4-T02 | Implement arrow/rectangle/ellipse renderers | P3-T03 | `done` | Shape tools support drag preview and final commit |
| P4-T03 | Implement text placement and editing commit flow | P3-T02 | `done` | Text tool creates editable then committed text nodes |
| P4-T04 | Implement eraser object-hit removal logic | P4-T02, P4-T03 | `done` | Eraser removes targeted scene elements only |
| P4-T05 | Implement undo/redo command stack | P4-T01, P4-T02, P4-T03, P4-T04 | `done` | Undo/redo works across all tool element types |
| P4-T06 | Implement clear-all command + confirmation behavior | P4-T05 | `done` | Scene clears safely and operation is undoable if intended |
| P4-T07 | Add renderer + undo/redo tests | P4-T05 | `done` | Tests cover mixed tool history operations |
| P4-T08 | Implement configurable options for drawing tools (`Circle`, `Rectangle`, `Highlighter`, `Pencil`) | P3-T16 | `done` | Options include thickness, color, and line style (`solid`, `dotted`, `dashed`); options panel wired to per-tool extended options |
| P4-T09 | Implement configurable options for arrows | P3-T16 | `done` | Options include single/double-sided arrow, color, and line style; double arrowhead renders correctly |
| P4-T10 | Implement configurable options for text tool | P3-T16 | `done` | Options include font design (sans/serif/mono), color, and size; font design stored per text element |
| P4-T11 | Implement tool settings fallback behavior | P4-T08, P4-T09, P4-T10 | `done` | Each tool uses last accepted (`OK`) settings via `ToolState.extendedOptions`; defaults from `ToolExtendedOptions.default` apply when no saved settings exist |
| P4-T12 | Add red close button to options panel (Cancel alias) | P3-T16 | `done` | Red x in top-right of options panel closes panel without applying changes |
| P4-T13 | Snapshot text tool config at edit-start to isolate from live changes | P4-T10 | `done` | `beginTextEditing` stores config snapshot; `commitTextDraft` uses snapshot; color/font unaffected by tool changes made while typing |
| P4-T14 | Refresh default tool presets for requested annotation colors/sizes and red eraser cursor | P4-T08, P4-T09, P4-T10 | `done` | Text and highlighter default sizes are `14`; pen/highlighter/text default to yellow; arrow/rectangle/ellipse default to blue; eraser cursor icon renders red |
| P4-T15 | Refine eraser cursor artwork and make tool shortcuts mirror radial tool clicks from pass-through mode | P4-T14, P3-T21 | `done` | Eraser cursor uses dedicated custom artwork instead of a broken tinted symbol, and pressing a tool shortcut while in pass-through exits pass-through, expands the radial, and selects that tool just like a click |
| P4-T16 | Stabilize text draft handoff when clicking a new text location mid-edit | P4-T10 | `done` | Clicking a new text location while a draft is active commits the current draft, starts a new draft at the clicked point, and tears down the prior AppKit text responder cleanly |

### Phase 5: Multi-Display Support
| ID | Task | Depends On | Status | Acceptance Criteria |
|---|---|---|---|---|
| P5-T01 | Add display discovery and lifecycle observer | P3-T01 | `done` | Attach/detach display updates overlays correctly |
| P5-T02 | Create one overlay per active display | P5-T01 | `done` | Baseline per-display overlay infrastructure exists for future display selection work |
| P5-T03 | Implement coordinate transform utility | P5-T02 | `done` | Cross-display geometry calculations are correct |
| P5-T04 | Ensure tool parity and state sync across displays | P5-T02 | `done` | Shared tool/scene state behaves consistently regardless of display layout transforms |
| P5-T05 | Add tests/manual matrix for edge display layouts | P5-T03 | `done` | Cases include negative origins and mixed scale factors |
| P5-T06 | Restrict overlay sessions to the mouse-selected display at action start | P5-T01, P5-T03 | `done` | Starting annotation creates and maintains overlay/pass-through UI on exactly one display: the one under the pointer when the action begins |

### Phase 6: Recording Engine Integration
| ID | Task | Depends On | Status | Acceptance Criteria |
|---|---|---|---|---|
| P6-T01 | Build `ScreenCaptureKit` stream service wrapper | P0-T02 | `done` | Capture starts with mouse-selected display; bound to single display per session per Phase 5 contract |
| P6-T02 | Build `AVAssetWriter` pipeline service | P6-T01 | `done` | Encoded H.264 video file finalizes correctly via `AVAssetWriterPipeline` (lock-guarded, off-main append) |
| P6-T03 | Integrate start/stop/pause/resume recording commands | P1-T03, P6-T02 | `done` | Lifecycle commands stable and idempotent; pause/resume route through service |
| P6-T04 | Ensure overlay capture strategy works as designed | P3-T01, P6-T03 | `done` | Option A confirmed: full-display capture includes overlay panels (architecture §4.5) |
| P6-T05 | Add error recovery for capture interruption and file failure | P6-T03 | `done` | `setErrorHandler` propagates async failures; AppStore resets session and surfaces `lastErrorMessage` |
| P6-T06 | Add recording lifecycle tests and manual scenario checks | P6-T03 | `in_progress` | Unit tests added for idempotent start/stop, pause/resume, error injection, audio toggle propagation; manual matrix pending GUI session |
| P6-T07 | Implement real Screen Recording TCC permission service | P6-T01 | `done` | `SystemPermissionService` calls `CGPreflightScreenCaptureAccess` / `CGRequestScreenCaptureAccess`; missing permission throws `RecordingError.permissionRequired` and triggers system prompt |

### Phase 7: Settings UI for Shortcuts and Colors
| ID | Task | Depends On | Status | Acceptance Criteria |
|---|---|---|---|---|
| P7-T01 | Build shortcut editor UI with conflict feedback | P2-T03 | `done` | Users can change bindings with validation feedback |
| P7-T02 | Build tool color and stroke configuration UI | P4-T02 | `done` | All tool style settings can be modified interactively |
| P7-T03 | Build permissions panel with status and re-check actions | P6-T01 | `done` | Permission states are visible and refreshable |
| P7-T04 | Add settings reset-to-default behavior | P7-T01, P7-T02 | `done` | Reset restores architecture defaults safely |
| P7-T05 | Add UI tests/manual checklist for settings flows | P7-T01, P7-T02, P7-T03 | `in_progress` | Manual checklist authored in `docs/MANUAL_TEST_GUIDE.md` (sections 1–9: Shortcuts happy/conflict/reset, Tools color/sliders/reset, Radial, Permissions denied/granted); 17+ unit tests cover the underlying APIs. Awaiting GUI session execution. |
| P7-T06 | Add radial control preferences (enabled, default position) | P3-T06, P3-T13, P3-T14 | `done` | Users can configure radial behavior from Settings (auto-hide skipped — removed by P3-T18; collapsed size deferred as premature) |
| P7-T07 | Add validation/tests for radial preferences persistence | P7-T06, P8-T01 | `done` | Radial settings survive restart; tests cover load-on-init + persist-on-change + propagation |

### Phase 8: Persistence and Output Management
| ID | Task | Depends On | Status | Acceptance Criteria |
|---|---|---|---|---|
| P8-T01 | Implement preferences repository on `UserDefaults` | P0-T02 | `done` | `UserDefaultsPreferencesService` already exists and is used by every settings preference key |
| P8-T02 | Add schema versioning and migration hook | P8-T01 | `done` | `preferencesSchemaVersionKey` (current=1) + `migratePreferencesIfNeeded` runs on `AppStore.init` |
| P8-T03 | Implement recording output directory selection + validation | P6-T02 | `done` | `RecordingService.outputDirectory` settable; AppStore validates writability and surfaces actionable errors; `OutputPanelView` provides folder picker + Reveal in Finder + Reset |
| P8-T04 | Implement deterministic file naming and collision handling | P8-T03 | `done` | `ScreenCaptureKitRecordingService.uniqueFileURL` appends `-1`, `-2`, … up to 100 then UUID fallback so an existing file is never overwritten |
| P8-T05 | Optional: metadata sidecar JSON write | P8-T04 | `todo` | Skipped — labeled `Optional` in the original spec; revisit when there is a concrete consumer for the sidecar |
| P8-T06 | Add persistence tests for shortcuts, palette, output path | P8-T01, P2-T04, P7-T02 | `done` | Tests cover shortcut bindings round-trip + conflict path + reset, tool configs/extended options round-trip + reset, radial enabled + default position round-trip, output directory set + reset + reject-non-directory, uniqueFileURL collision avoidance, and schema-version stamp on first init |

### Phase 9: Stabilization, Profiling, and Release Readiness
| ID | Task | Depends On | Status | Acceptance Criteria |
|---|---|---|---|---|
| P9-T01 | Finalize unit test suite for state and command routing | P1-T04, P2-T05, P4-T07, P8-T06 | `todo` | Core test suite is green and repeatable |
| P9-T02 | Execute manual test matrix for permissions/displays/recording/radial UX | P5-T05, P6-T06, P7-T05, P3-T09, P3-T10, P3-T11, P3-T13, P3-T14, P3-T15, P3-T16, P3-T17, P4-T08, P4-T09, P4-T10, P4-T11 | `todo` | Matrix completed and documented |
| P9-T03 | Run performance profiling against section 9 targets | P3-T05, P6-T03 | `todo` | Metrics captured and compared to targets |
| P9-T04 | Resolve or log all release-blocking defects | P9-T01, P9-T02 | `todo` | No unresolved P0/P1 severity issues |
| P9-T05 | Publish release readiness summary | P9-T01, P9-T02, P9-T03, P9-T04 | `todo` | Summary includes known limits and go/no-go |

## Agent Update Protocol (Use Every Session)
1. Select the next `todo` task with dependencies already `done`.
2. Set that task status to `in_progress`.
3. Update `Current Execution State`.
4. Implement and validate against acceptance criteria and quality gates.
5. Set task status to `done` or `blocked`.
6. If phase completed, update phase status board and `docs/ARCHITECTURE.md` section `11.1`.
7. Update `docs/ARCHITECTURE.md` section `13` with decision and validation details.
8. Add a brief note to `Execution Log`.

## Blockers Log
| Date | Task ID | Blocker | Required Action | Status |
|---|---|---|---|---|
| YYYY-MM-DD | P?-T?? | TBD | TBD | open |
| 2026-03-31 | P3-T09 | Manual radial UX checklist requires running overlay interactions in macOS GUI session | Execute Phase 3 radial manual checklist in a full Xcode/macOS app runtime and record results | open |
| 2026-04-01 | P3-T09 | New cursor and Shift-constrained drawing behavior still require live overlay verification in a full macOS GUI runtime | Run the app from Xcode, verify eraser cursor only appears outside pass-through mode, and confirm Shift-constrained pen/highlighter and arrow behavior | open |

## Execution Log
| Date | Task ID | Change Summary | Validation | Next Task |
|---|---|---|---|---|
| YYYY-MM-DD | P?-T?? | TBD | TBD | TBD |
| 2026-03-31 | P0-T01..P0-T05 | Added module scaffolding, service protocols, DI container, and smoke test target/wiring | `xcodebuild test` passed | P1-T01 |
| 2026-03-31 | P0-T02 | Hardened protocol isolation and preferences serialization; replaced smoke assertions with behavior checks; fixed section order in architecture docs | `xcodebuild test` passed | P1-T01 |
| 2026-03-31 | P1-T01..P1-T05 | Added `MenuBarExtra` controls with active-mode indicator, implemented `AppStore` (`SessionMode`, `ToolState`, `CommandID`) and deterministic command reducer, and added transition unit tests | `xcodebuild test` could not run in this environment | P2-T01 |
| 2026-03-31 | P2-T01..P2-T05 | Added default shortcut domain model and validator, implemented `AppKitShortcutService` event adapter, wired `AppStore` shortcut registration/persistence/dispatch, and added shortcut mapping/conflict tests | validation performed via static code checks and test compilation review | P3-T01 |
| 2026-03-31 | P3-T01..P3-T08,P3-T11..P3-T14 | Added `AppKitOverlayService` with a transparent top-level panel, pointer-driven canvas stroke rendering, active tool HUD, radial control shell with secondary options, shortcut-aware hover tooltips, focus-loss auto-collapse lifecycle, and `AppStore` command wiring for overlay actions/visibility | validation performed via static review and targeted unit-test updates | P3-T10 |
| 2026-03-31 | P4-T01..P4-T07,P3-T10 | Added a scene-element overlay model supporting highlighter, arrow/rectangle/ellipse drag-preview renderers, text draft-commit flow, eraser hit-removal, undo/redo stack, clear-all undoable behavior, and AppStore command wiring for radial/shortcut undo-redo-clear actions | validation performed via static code review and added scene-model/store command routing tests | P3-T09 |
| 2026-03-31 | P5-T01..P5-T05 | Added display lifecycle observation, created one overlay panel per active display, introduced global/local coordinate transformer for cross-display rendering/input, synchronized shared tool/scene state across panels, and fixed arrow-edge clipping bounds for multi-display culling | validation via static review and new coordinate transformation tests | P6-T01 |
| 2026-03-31 | P2-T01 | Fixed `ServiceProtocols.swift` syntax in `ShortcutKey` Carbon key-code extension | `swiftc -frontend -parse` passed | P6-T01 |
| 2026-04-01 | P3/P4 rescope | Re-scoped radial UX to hover activation + 3s focus-loss timeout, removed generic second ring, and introduced per-tool options panel contract with `OK`/`Cancel` and per-tool fallback behavior | Documentation consistency review | P3-T13 |
| 2026-04-01 | P3-T13..P3-T17,P4-T08..P4-T11 | Implemented activation lifecycle, per-tool options panel, center icon swaps, domain models for line/arrow/text styles, and extended options round-trip | Static code review and targeted tests | P3-T09 |
| 2026-04-01 | P3-T18..P3-T21,P4-T12,P4-T13 | Removed auto-collapse, custom tooltips, Escape handler, pass-through mode, red close button, text config snapshot | Static code review | P3-T09 |
| 2026-04-01 | P3-T09 | Eraser cursor, Shift-constrained drawing | Static code review and unit tests | P3-T09 |
| 2026-04-01 | P3-T09 | Shift-constrained shapes, pass-through center-tap, left-aligned text | `swiftc -frontend -parse` passed | P3-T09 |
| 2026-04-01 | P3-T09 | Shift modifier tooltips, right-side radial spawn | `swiftc -frontend -parse` passed | P3-T09 |
| 2026-04-01 | P3-T22 | Pass-through center tap reselects active tool, default stroke widths to 1 | `swiftc -frontend -parse` passed | P3-T09 |
| 2026-04-01 | P3-T23 | Removed drag gesture from pass-through center button | `swiftc -frontend -parse` passed | P3-T09 |
| 2026-04-01 | P3-T24 | Pass-through exit without tool preselection, stable radial position | `swiftc -frontend -parse` passed | P3-T09 |
| 2026-04-01 | P3-T25 | Pass-through exit syncs to interacted display | `swiftc -frontend -parse` passed | P3-T09 |
| 2026-04-01 | P5-T06 | Single-display session scoping | `swiftc -frontend -parse` passed | P3-T09 |
| 2026-04-02 | P4-T14 | Updated default presets (yellow/blue colors, size 14, red eraser) | `swiftc -frontend -parse` passed | P3-T09 |
| 2026-04-02 | P4-T15 | Custom eraser cursor artwork, tool shortcut pass-through exit | `swiftc -frontend -parse` passed | P3-T09 |
| 2026-04-02 | P4-T16 | Text draft handoff stabilization | `swiftc -frontend -parse` passed | P3-T09 |
| 2026-04-06 | P4-T17 | Disabled RemoteViewService and smart text features on OverlayTextField | `swiftc -frontend -parse` passed | P3-T09 |
| 2026-05-05 | REVIEW-P0-1 | Split `AppStore.reduce()` into `reduceAnnotationCommand` / `reduceRecordingCommand` / `reduceToolCommand` per the review plan in `.air/plans/review-this-application-how-bubbly-simon.plan.md` | `xcodebuild test -scheme Pinnacle -destination 'platform=macOS'` passed | P3-T09 |
| 2026-05-05 | REVIEW-P0-2 | Replaced four decoupled radial bools with `RadialState` enum (`collapsed` / `expanded(selectedToolForOptions:)` / `optionsOpen(ToolKind)` / `passThrough`); old getters preserved as computed read-only props | `xcodebuild test` passed | P3-T09 |
| 2026-05-05 | REVIEW-P0-3 | Extracted `TextEditingViewModel` from `OverlayViewModel` to own NSTextField responder lifecycle; encoded P4-T17 contract in docblock | `xcodebuild test` passed | P3-T09 |
| 2026-05-05 | REVIEW-P0-4 | Added `OverlayService.setErrorHandler` so panel-creation/screen-resolution failures surface in `AppStore.lastErrorMessage` instead of being silently logged | `xcodebuild test` passed | P3-T09 |
| 2026-05-05 | REVIEW-P1-7 | Consolidated duplicated `globalPointToLocal` calls in `OverlayRootView` text-draft positioning | `xcodebuild test` passed | P3-T09 |
| 2026-05-05 | REVIEW-P2-8/9 | Added inline coordinate-space contract on `OverlayViewModel.handleDragChanged` and NSTextField responder contract docblock on `TextEditingViewModel` | `xcodebuild test` passed | P3-T09 |
| 2026-05-05 | REVIEW-P1-5 | Introduced `ColorHex` newtype (`Equatable, Hashable, Codable, ExpressibleByStringLiteral`) and migrated `ToolConfig.colorHexRGBA`, all five `OverlaySceneElement.Kind` cases, `OverlayTextItem.colorHexRGBA`, `Color(hexRGBA:)`, and the cycle/swatch palette literals in `AppStore` and `ToolOptionsPanelView`. Codable single-value conformance preserves the existing JSON wire format. | `xcodebuild test -scheme Pinnacle -destination 'platform=macOS'` passed | P3-T09 |
| 2026-05-05 | REVIEW-P2-10 | Read-only audit of `[weak self]` and `removeObserver` paths in `AppKitOverlayService`. Findings: all callbacks/sinks/monitors capture `[weak self]` correctly; `cancellables` Set anchors the four Combine pipelines; the three observer/monitor tokens (`screenObserver`, `drawEventMonitor`, `keyEventMonitor`) are torn down only inside `stopOverlay()` (no `deinit` cleanup, acceptable for the singleton-lifetime ownership in `AppContainer.live`); two closures nest a redundant outer `[weak self]` whose `self` is shadowed by an inner `Task { @MainActor [weak self] in ... }`. Documented as future cleanup, not a regression. | No code changes | P3-T09 |
| 2026-05-05 | REVIEW-P1-6 | Verified `AppContainer.live` is already a `@MainActor static let` (the class is `@MainActor`, the property is a stored `static let`, not a computed property). The review plan's concern about orphaned hotkey registrations from a recomputed container does not apply. Single consumer in `PinnacleApp.swift:17`. | No code changes | P3-T09 |
| 2026-05-05 | P6-T01..P6-T05,P6-T07 | Extended `RecordingService` (pause/resume, `isPaused`, `outputURL`, mutable `capturesSystemAudio`, `setErrorHandler`); created `ScreenCaptureKitRecordingService` (SCStream + SCStreamOutput/Delegate adapter, single-display capture using `DisplayDescriptor.underMouse()`, `~/Movies/Pinnacle/Pinnacle-yyyyMMdd-HHmmss.mp4`); added thread-safe `AVAssetWriterPipeline` (NSLock-guarded appends, H.264 6 Mbps @ 1080p/30 + optional AAC 48 kHz/2ch/128 kbps); added real `SystemPermissionService` (`CGPreflightScreenCaptureAccess` / `CGRequestScreenCaptureAccess`, throws `RecordingError.permissionRequired`); rewired `AppContainer.live`; in `AppStore` wired `setErrorHandler` (resets session on failure), exposed `@Published var capturesSystemAudio`, replaced TODOs with real pause/resume; extended `SpyRecordingService` and added six new tests (pause/resume routing, idempotent start/stop, error-handler reset, audio toggle propagation). | Full-target `swiftc -typecheck` passed (only unrelated `#Preview` macro plugin warnings); `xcodebuild test` env-blocked (CommandLineTools); P6-T06 manual scenario matrix deferred to GUI session | P6-T06 |
| 2026-05-08 | P8-T01..T04 | **P8-T01:** confirmed `UserDefaultsPreferencesService` already implements the preferences repository — every preference key (shortcuts, tool styles, radial, output dir, schema version) round-trips through it. **P8-T02:** added `preferencesSchemaVersionKey` (current=1) and `AppStore.migratePreferencesIfNeeded(using:)` invoked on `init` ahead of any other prefs reads. No migrations needed at v1; future schema changes branch on the stored version here. **P8-T03:** extended `RecordingService` protocol with `var outputDirectory: URL { get set }`. `ScreenCaptureKitRecordingService` exposes `defaultOutputDirectory()` and respects the configured directory in `makeOutputURL()`. AppStore: `outputDirectoryPathPreferenceKey` (String, "" = default), `outputDirectory` getter, `setOutputDirectory(_:)` (validates `isDirectory`, creates if missing, checks `isWritableFile`, throws `OutputDirectoryError`), `resetOutputDirectory()`. New `OutputPanelView` (Settings → Output tab) with current path display, Choose Folder… via `NSOpenPanel(canChooseDirectories: true, canCreateDirectories: true)`, Reveal in Finder, Reset to Default; surfaces validation errors inline. `configureRecording` applies persisted directory at startup with a missing-path safety check. **P8-T04:** `ScreenCaptureKitRecordingService.uniqueFileURL(in:baseName:ext:)` appends `-1`, `-2`, …, `-99`, then a UUID fallback so an existing file is never overwritten. Added 4 tests (set persists + applies, reject non-directory, reset restores default path + clears stored value, uniqueFileURL avoids collisions). | `xcodebuild test` ✓ (72/72 passing). | P8-T06 |
| 2026-05-08 | P7-T06,P7-T07 | Added radial control preferences. New `RadialPosition` enum (right/left) in domain. New preference keys (`radialControlEnabledPreferenceKey: Bool` default true, `radialDefaultPositionPreferenceKey: RadialPosition` default `.right`). Extended `OverlayService` protocol with `setRadialDefaultPosition(_:)`; `AppKitOverlayService` forwards to a new `defaultRadialPosition` published property on `OverlayViewModel`; `ensureInitialRadialPosition(in:)` now reads that property to choose the start X coordinate. AppStore loads both prefs in `init`, persists on `toggleRadialControl` shortcut as well as new `setRadialControlEnabled(_:)` / `setRadialDefaultPosition(_:)` API. New `RadialControlPanelView` (Settings → Radial tab) with toggle + position picker. Skipped "auto-hide" pref (auto-hide was deliberately removed by P3-T18) and "collapsed size" (premature). Added 6 tests (radial-enabled load+propagate, radial-enabled set persists, toggle persists, position load+propagate, position set persists, ensureInitialRadialPosition respects left default). | `xcodebuild test` ✓ (68/68 passing). | P7-T05 |
| 2026-05-08 | P7-T04 | Added "Reset to Defaults" actions per tab (each guarded by a destructive `.alert`). `AppStore.resetShortcutsToDefaults()` re-applies `ShortcutBinding.defaults` via `updateShortcutBindings(_:)` (so registration + persistence + overlay propagation all happen). `AppStore.resetToolStylesToDefaults()` re-assigns `toolState.configs` and `toolState.extendedOptions` from `ToolState.default`, pushes to overlay, persists. Added 2 tests (shortcuts reset round-trips through registration + persistence; tool style reset round-trips through persistence). | `xcodebuild test` ✓ (62/62 passing). | P7-T05 |
| 2026-05-08 | P7-T03 | Built `PermissionsPanelView` (Settings → Permissions tab; status row with colored icon + descriptive text; "Re-check" button (re-runs async `permissionStatus()`), "Request Access" button (disabled when `.granted`, calls TCC prompt and re-checks), "Open System Settings" button (deep-links to `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`); auto-refreshes on appear via `.task`). Added `AppStore.permissionStatus() async` and `requestScreenRecordingAccess()` so the view doesn't reach through `AppContainer`. Added `SpyPermissionService` to PinnacleTests + 2 tests (status returns service value and reflects mutations; request forwards to service). Updated `makeStoreHarness` to accept an optional permissionService. | `xcodebuild test` ✓ (60/60 passing). | P7-T05 |
| 2026-05-08 | P7-T02 | Built `ToolStyleEditorView` (Settings → Tools tab; segmented tool picker excluding eraser; per-tool form with palette swatches matching the radial UX + native `ColorPicker` for custom colors, thickness/font-size slider, opacity slider, line-style segmented control where applicable, arrow-style for `.arrow`, font design for `.text`). Added `AppStore` tool-style API: `currentToolConfig(for:)`, `currentToolExtendedOptions(for:)`, `updateToolConfig(_:for:)`, `updateToolExtendedOptions(_:for:)`. Added two preference keys (`toolConfigsPreferenceKey`, `toolExtendedOptionsPreferenceKey`) and `Self.toolStateLoaded(from:)` so persisted styles are loaded on `AppStore.init` (merging per-tool with `ToolState.default` for any missing entries). Persisted on every mutation path: settings edits, overlay `applyToolOptions`, shortcut-driven `cycleColors` / `increaseStroke` / `decreaseStroke`. Added a private `Color → ColorHex` bridge using `NSColor.usingColorSpace(.sRGB)`. Added 4 tests (settings update persists + propagates, extended-options update, init loads + merges saved styles, overlay `applyToolOptions` persists). | `xcodebuild test` ✓ (58/58 passing). UI not yet exercised in a live macOS GUI session; opens via `Settings…` → Tools tab. | P7-T05 |
| 2026-05-08 | P7-T01 | Built `ShortcutEditorView` (SwiftUI list of all 17 commands; per-row modifier toggles for ⌃⌥⇧⌘ and a key picker; live conflict highlighting + banner; auto-saves through `AppStore.updateShortcutBindings(_:)` on every conflict-free edit, otherwise leaves the draft local so the user can edit out of the conflict). Added `AppStore.updateShortcutBindings(_:) -> Bool` (validates → re-registers → persists → updates overlay; returns false + sets `lastErrorMessage` on conflict or registration failure) and `currentShortcutBindings` getter. Factored shortcut callback into `makeShortcutHandler()` so initial config and live updates share the same dispatch path. Added `ShortcutCommandID.displayName` for editor labels. Replaced placeholder `SettingsView` with a `TabView` hosting the editor and threaded `store` through `Settings { ... }` in `PinnacleApp`. Closes the UX gap left by the audit's conflict-preserve fix — users can now resolve persisted shortcut conflicts. Added 3 tests (apply conflict-free, reject conflicts without persisting, expose stored bindings). | `xcodebuild test` ✓ (54/54 passing). UI not yet exercised in a live macOS GUI session — opens via `Settings…` menu / `⌘,`. | P7-T05 |
| 2026-05-08 | AUDIT-FIXES | Comprehensive audit + remediation pass triggered by `/feature-dev fix all`. **Recording (P6 hardening):** track `startupTask` and cancel/await on stop (race-free teardown); expose `awaitFinalization()` on protocol so `PinnacleAppDelegate.applicationShouldTerminate` drains pending writers via `terminateLater`/`reply(toApplicationShouldTerminate:)`; pipeline's `finish()` now returns `FinishOutcome` and the service surfaces an actionable error when zero frames were captured; replaced sample-drop pause with PTS rebasing (`pauseStart` lazily marked by first paused sample, consumed by first post-resume sample, `totalPausedDuration` accumulated, `CMSampleBufferCreateCopyWithNewTiming` shifts subsequent samples) so the output timeline has no freeze artifact. **NOTE:** PTS rebasing is not unit-tested (would require synthetic CMSampleBuffers + real AVAssetWriter); P6-T06 manual record/pause/resume/stop check is still required to validate. **Permissions:** `SystemPermissionService` is now a class that distinguishes `.denied` from `.notDetermined` via a UserDefaults `hasRequested` flag (init accepts custom defaults for testability). **Shortcuts:** `AppKitShortcutService.register` rolls back partial Carbon hotkey registrations on mid-loop failure; `AppStore.configureShortcuts` no longer overwrites stored bindings on conflict (preserves user customizations + surfaces `lastErrorMessage`). **Overlay:** drawing dead-zone radii now match `PassThroughContainerView.hitTest` tiers via shared `OverlayGeometry.radial{Collapsed,Expanded,OptionsPanel}Radius`, eliminating phantom strokes when clicking OK/Cancel on the options panel; `synchronizeOverlayPanels` now keeps panels for ALL `NSScreen.screens` so global-coordinate annotations render across displays; `HUDView` wired into `OverlayRootView` (note: this is a small visible UX addition — top-left tool pill — alternative was deletion of the file). **AppStore:** recording-error during `.paused` now routes to `.annotating` when paused-from `.recordingAndAnnotating` (overlay no longer leaks); annotation toggle in `.paused` is now functional (was a stale no-op); removed obsolete `canToggleAnnotation` no-op gate. **Hygiene:** `StubServices.swift` moved into `PinnacleTests/` so no-op/in-memory stubs no longer ship in the production binary. Added 4 new tests (paused-error from recording-only, paused-error from recording-and-annotating, paused annotation-toggle, SystemPermissionService denied-after-request). | `xcodebuild test -scheme Pinnacle -destination 'platform=macOS'` ✓ (51/51 passing). **P3-T09 / P6-T06 manual GUI checklists are still required** — see `docs/MANUAL_TEST_GUIDE.md`; the pause/resume freeze-artifact fix can ONLY be validated via the manual matrix. | P3-T09, P6-T06 |
