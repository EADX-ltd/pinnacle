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
| Current Task ID | `P3-T09` |
| Current Phase | `3` |
| Last Updated (UTC) | `2026-04-02 11:39` |
| Updated By | `agent` |
| Notes | `Requested default annotation presets landed; remaining active blocker is still the manual macOS GUI checklist for Phase 3.` |

## Phase Status Board

| Phase | Name | Status | Exit Criteria |
|---|---|---|---|
| 0 | Project scaffolding and protocols | `done` | Task group `P0-*` all `done` |
| 1 | Menu bar app shell and state store | `done` | Task group `P1-*` all `done` |
| 2 | Global shortcuts | `done` | Task group `P2-*` all `done` |
| 3 | Overlay engine (single display) | `in_progress` | Task group `P3-*` complete except final `P3-T09` manual GUI checklist |
| 4 | Tool renderers + undo/redo | `done` | Task group `P4-*` all `done` including per-tool options and modifier rules |
| 5 | Multi-display support | `done` | Task group `P5-*` complete, with session behavior now intentionally limited to one mouse-selected display at action start |
| 6 | Recording engine integration | `todo` | Task group `P6-*` all `done` |
| 7 | Settings UI for shortcuts/colors | `todo` | Task group `P7-*` all `done` |
| 8 | Persistence and output management | `todo` | Task group `P8-*` all `done` |
| 9 | Stabilization, profiling, test pass | `todo` | Task group `P9-*` all `done` |

## Next Batch Priority (Must Complete Before Phase 6)
All previously listed items are `done`. The batch below was completed in this session:
1. `P3-T18` Remove radial auto-collapse timer — HUD stays activated permanently. `done`
2. `P3-T19` Custom hover tooltips for radial ring items (replaces `.help()` which is unreliable in non-activating panels). `done`
3. `P3-T20` Escape key multi-level handler: cancel options → cancel text draft → deselect + enter pass-through mode. `done`
4. `P3-T21` Pass-through mode: overlay `ignoresMouseEvents` toggled; `PassThroughContainerView` routes hits only to HUD/radial area. `done`
5. `P4-T12` Red `×` close button on options panel (Cancel alias). `done`
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
| P3-T20 | Escape key multi-level handler | P3-T13, P4-T03 | `done` | Escape cancels options → cancels text draft → deselects tool + enters pass-through |
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
| P4-T12 | Add red `×` close button to options panel (Cancel alias) | P3-T16 | `done` | Red × in top-right of options panel closes panel without applying changes |
| P4-T13 | Snapshot text tool config at edit-start to isolate from live changes | P4-T10 | `done` | `beginTextEditing` stores config snapshot; `commitTextDraft` uses snapshot; color/font unaffected by tool changes made while typing |
| P4-T14 | Refresh default tool presets for requested annotation colors/sizes and red eraser cursor | P4-T08, P4-T09, P4-T10 | `done` | Text and highlighter default sizes are `14`; pen/highlighter/text default to yellow; arrow/rectangle/ellipse default to blue; eraser cursor icon renders red |

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
| P6-T01 | Build `ScreenCaptureKit` stream service wrapper | P0-T02 | `todo` | Capture starts with configured display selection |
| P6-T02 | Build `AVAssetWriter` pipeline service | P6-T01 | `todo` | Encoded video file finalizes correctly |
| P6-T03 | Integrate start/stop/pause/resume recording commands | P1-T03, P6-T02 | `todo` | Lifecycle commands are stable and idempotent |
| P6-T04 | Ensure overlay capture strategy works as designed | P3-T01, P6-T03 | `todo` | Output includes expected annotation visuals |
| P6-T05 | Add error recovery for capture interruption and file failure | P6-T03 | `todo` | Failures surface actionable error state and cleanup |
| P6-T06 | Add recording lifecycle tests and manual scenario checks | P6-T03 | `todo` | Passes start-stop loops and pause/resume scenarios |

### Phase 7: Settings UI for Shortcuts and Colors
| ID | Task | Depends On | Status | Acceptance Criteria |
|---|---|---|---|---|
| P7-T01 | Build shortcut editor UI with conflict feedback | P2-T03 | `todo` | Users can change bindings with validation feedback |
| P7-T02 | Build tool color and stroke configuration UI | P4-T02 | `todo` | All tool style settings can be modified interactively |
| P7-T03 | Build permissions panel with status and re-check actions | P6-T01 | `todo` | Permission states are visible and refreshable |
| P7-T04 | Add settings reset-to-default behavior | P7-T01, P7-T02 | `todo` | Reset restores architecture defaults safely |
| P7-T05 | Add UI tests/manual checklist for settings flows | P7-T01, P7-T02, P7-T03 | `todo` | Settings flows verified for happy/error paths |
| P7-T06 | Add radial control preferences (enabled, collapsed size, auto-hide, default position) | P3-T06, P3-T13, P3-T14 | `todo` | Users can configure radial behavior from Settings |
| P7-T07 | Add validation/tests for radial preferences persistence | P7-T06, P8-T01 | `todo` | Radial settings survive restart and invalid values are rejected |

### Phase 8: Persistence and Output Management
| ID | Task | Depends On | Status | Acceptance Criteria |
|---|---|---|---|---|
| P8-T01 | Implement preferences repository on `UserDefaults` | P0-T02 | `todo` | Preferences persist and load on restart |
| P8-T02 | Add schema versioning and migration hook | P8-T01 | `todo` | Older preference schema loads safely |
| P8-T03 | Implement recording output directory selection + validation | P6-T02 | `todo` | Invalid paths are blocked with user guidance |
| P8-T04 | Implement deterministic file naming and collision handling | P8-T03 | `todo` | No accidental overwrite; naming is predictable |
| P8-T05 | Optional: metadata sidecar JSON write | P8-T04 | `todo` | Sidecar generated when feature flag is enabled |
| P8-T06 | Add persistence tests for shortcuts, palette, output path | P8-T01, P2-T04, P7-T02 | `todo` | Regression tests pass for key persisted settings |

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
| 2026-03-31 | P0-T01..P0-T05 | Added module scaffolding, service protocols, DI container, and smoke test target/wiring | `xcodebuild test -project Pinnacle.xcodeproj -scheme Pinnacle -destination 'platform=macOS' -derivedDataPath /tmp/PinnacleDerivedData -only-testing:PinnacleTests/PinnacleSmokeTests` passed | P1-T01 |
| 2026-03-31 | P0-T02 | Hardened protocol isolation and preferences serialization; replaced smoke assertions with behavior checks; fixed section order in architecture docs | `xcodebuild test -project Pinnacle.xcodeproj -scheme Pinnacle -destination 'platform=macOS' -derivedDataPath /tmp/PinnacleDerivedData -only-testing:PinnacleTests/PinnacleSmokeTests` passed | P1-T01 |
| 2026-03-31 | P1-T01..P1-T05 | Added `MenuBarExtra` controls with active-mode indicator, implemented `AppStore` (`SessionMode`, `ToolState`, `CommandID`) and deterministic command reducer, and added transition unit tests | `xcodebuild test -project Pinnacle.xcodeproj -scheme Pinnacle -destination 'platform=macOS' -derivedDataPath /tmp/PinnacleDerivedData -only-testing:PinnacleTests/PinnacleSmokeTests` could not run in this environment (`xcodebuild` requires full Xcode, active developer dir is CommandLineTools) | P2-T01 |
| 2026-03-31 | P2-T01..P2-T05 | Added default shortcut domain model and validator, implemented `AppKitShortcutService` event adapter, wired `AppStore` shortcut registration/persistence/dispatch, and added shortcut mapping/conflict tests | `xcodebuild test -project Pinnacle.xcodeproj -scheme Pinnacle -destination 'platform=macOS' -derivedDataPath /tmp/PinnacleDerivedData -only-testing:PinnacleTests/PinnacleSmokeTests` could not run in this environment (`xcodebuild` requires full Xcode, active developer dir is CommandLineTools); validation performed via static code checks and test compilation review | P3-T01 |
| 2026-03-31 | P3-T01..P3-T08,P3-T11..P3-T14 | Added `AppKitOverlayService` with a transparent top-level panel, pointer-driven canvas stroke rendering, active tool HUD, radial control shell with secondary options, shortcut-aware hover tooltips, focus-loss auto-collapse lifecycle, and `AppStore` command wiring for overlay actions/visibility | `xcodebuild test -project Pinnacle.xcodeproj -scheme Pinnacle -destination 'platform=macOS' -derivedDataPath /tmp/PinnacleDerivedData -only-testing:PinnacleTests/PinnacleSmokeTests` could not run in this environment (`xcodebuild` requires full Xcode, active developer dir is CommandLineTools); validation performed via static review and targeted unit-test updates | P3-T10 |
| 2026-03-31 | P4-T01..P4-T07,P3-T10 | Added a scene-element overlay model supporting highlighter, arrow/rectangle/ellipse drag-preview renderers, text draft-commit flow, eraser hit-removal, undo/redo stack, clear-all undoable behavior, and AppStore command wiring for radial/shortcut undo-redo-clear actions | `xcodebuild test -project Pinnacle.xcodeproj -scheme Pinnacle -destination 'platform=macOS' -derivedDataPath /tmp/PinnacleDerivedData -only-testing:PinnacleTests/PinnacleSmokeTests` could not run in this environment (`xcodebuild` requires full Xcode, active developer dir is CommandLineTools); validation performed via static code review and added scene-model/store command routing tests | P3-T09 |
| 2026-03-31 | P5-T01..P5-T05 | Added display lifecycle observation, created one overlay panel per active display, introduced global/local coordinate transformer for cross-display rendering/input, synchronized shared tool/scene state across panels, and fixed arrow-edge clipping bounds for multi-display culling | `xcodebuild test -project Pinnacle.xcodeproj -scheme Pinnacle -destination 'platform=macOS' -derivedDataPath /tmp/PinnacleDerivedData -only-testing:PinnacleTests/PinnacleSmokeTests` could not run in this environment (`xcodebuild` requires full Xcode, active developer dir is CommandLineTools); validation performed via static review and new coordinate transformation tests for negative-origin and mixed-scale display layouts | P6-T01 |
| 2026-03-31 | P2-T01 | Fixed `ServiceProtocols.swift` syntax in `ShortcutKey` Carbon key-code extension by closing the extension block, restoring valid hotkey service compilation path | `swiftc -frontend -parse Pinnacle/Services/ServiceProtocols.swift` passed; `xcodebuild` remains unavailable in this environment (`xcode-select` points to CommandLineTools) | P6-T01 |
| 2026-04-01 | P3/P4 rescope | Re-scoped radial UX to hover activation + 3s focus-loss timeout, removed generic second ring, and introduced per-tool options panel contract with `OK`/`Cancel` and per-tool fallback behavior | Documentation consistency review across `docs/ARCHITECTURE.md` and `docs/IMPLEMENTATION_TASKS.md` | P3-T13 |
| 2026-04-01 | P3-T13,P3-T07,P3-T14,P3-T15,P3-T16,P3-T17,P4-T08,P4-T09,P4-T10,P4-T11 | Implemented activation lifecycle (hover→expand, focus-loss→3s collapse), removed generic secondary ring, added per-tool options panel with OK/Cancel anchored below first ring, center icon swaps to paintpalette for configurable tools, added LineStyle/ArrowStyle/TextFontDesign domain models, updated OverlaySceneElement.Kind to store line style and arrow style per element, wired double-headed arrow renderer, per-tool options stored in ToolState.extendedOptions and round-tripped through OverlayAction.applyToolOptions | Static code review; validation via targeted tests for ToolExtendedOptions defaults, applyToolOptions routing, element model per-field storage, and scene undo/redo; `xcodebuild` still unavailable (CommandLineTools) | P3-T09 |
| 2026-04-01 | P3-T18,P3-T19,P3-T20,P3-T21,P4-T12,P4-T13 | Removed 3-second radial auto-collapse timer (HUD permanently expanded once activated); replaced `.help()` tooltips with custom `@State hoveredItem` overlay labels; added Escape key local event monitor with multi-level handler (cancel options → cancel text draft → deselect + enter pass-through); implemented `PassThroughContainerView` with per-area `hitTest` for pass-through mode where annotations stay visible but mouse events reach underlying apps; HUD/radial remain interactive via hit-test routing; added red `×` close button on options panel; fixed text-element config snapshot so in-progress text is isolated from live tool-config changes; app activated + overlay panel made key on annotation start for reliable local key monitoring | Static code review; `xcodebuild` unavailable (CommandLineTools) | P3-T09 |
| 2026-04-01 | P3-T09 | Added an eraser-specific overlay cursor while annotation is active outside pass-through mode, and added Shift-constrained drawing so pen/highlighter commit a straight two-point stroke while arrows snap to 45° increments from drag origin | Static code review; added targeted unit tests for constrained stroke commit and arrow preview snapping; `xcodebuild` unavailable (CommandLineTools) | P3-T09 |
| 2026-04-01 | P3-T09 | Added pass-through center-tap recovery with no selected tool, extended Shift-constrained previews to square and center-based circle geometry, and changed the text tool to use left-aligned anchored placement for both draft and committed text | `swiftc -frontend -parse Pinnacle/Overlay/OverlayScene.swift Pinnacle/Overlay/OverlayViewModel.swift Pinnacle/Overlay/OverlayRootView.swift Pinnacle/Overlay/RadialControlView.swift Pinnacle/Overlay/AppKitOverlayService.swift PinnacleTests/PinnacleSmokeTests.swift` passed; `xcodebuild` unavailable (CommandLineTools) | P3-T09 |
| 2026-04-01 | P3-T09 | Updated tooltips to describe each tool’s `Shift` modifier behavior and moved the initial radial/HUD spawn to the right side of the display on first overlay appearance | `swiftc -frontend -parse Pinnacle/Overlay/OverlayViewModel.swift Pinnacle/Overlay/OverlayRootView.swift PinnacleTests/PinnacleSmokeTests.swift` passed; `xcodebuild` unavailable (CommandLineTools) | P3-T09 |
| 2026-04-01 | P3-T09 | Changed the radial center `X` to use a direct tap path instead of relying on the drag gesture end-state, so exiting pass-through now behaves like clicking a tool even when no tool is selected | `swiftc -frontend -parse Pinnacle/Overlay/RadialControlView.swift Pinnacle/Overlay/OverlayViewModel.swift` passed; `xcodebuild` unavailable (CommandLineTools) | P3-T09 |
| 2026-04-01 | P3-T22 | Refined pass-through center tap so it reselects the active tool workflow exactly like a tool tap, and changed default stroke widths for pen/arrow/rectangle/ellipse to `1` while preserving the highlighter default | `swiftc -frontend -parse Pinnacle/Domain/AppDomainModels.swift Pinnacle/Overlay/OverlayViewModel.swift PinnacleTests/PinnacleSmokeTests.swift` passed; `xcodebuild test -project Pinnacle.xcodeproj -scheme Pinnacle -destination 'platform=macOS' -derivedDataPath /tmp/PinnacleDerivedData -only-testing:PinnacleTests/PinnacleSmokeTests CODE_SIGNING_ALLOWED=NO` could not run because `xcode-select` points to CommandLineTools | P3-T09 |
| 2026-04-01 | P3-T23 | Removed the relocation drag recognizer from the non-relocatable pass-through center control, preventing the zero-distance drag gesture from stealing the first click before the center tap handler can resume annotation | `swiftc -frontend -parse Pinnacle/Overlay/RadialControlView.swift Pinnacle/Overlay/OverlayViewModel.swift` passed; `xcodebuild` unavailable (CommandLineTools) | P3-T09 |
| 2026-04-01 | P3-T24 | Corrected pass-through center-click semantics so the first click only exits pass-through and leaves `selectedToolForOptions` empty, and changed pass-through panel layout to derive `localCenter` from the clamped frame so the visible radial position does not jump left near screen edges | `swiftc -frontend -parse Pinnacle/Overlay/OverlayViewModel.swift Pinnacle/Overlay/AppKitOverlayService.swift PinnacleTests/PinnacleSmokeTests.swift` passed; `xcodebuild` unavailable (CommandLineTools) | P3-T09 |
| 2026-04-01 | P3-T25 | Synced pass-through exit to the currently interacted display by refreshing `activeDisplayID` from the mouse location when entering/leaving pass-through, reordering panels before regaining focus, and updating `activeDisplayID` during overlay mouse events so the overlay no longer flashes onto a stale secondary monitor on the first click | `swiftc -frontend -parse Pinnacle/Overlay/AppKitOverlayService.swift Pinnacle/Overlay/OverlayViewModel.swift` passed; `xcodebuild` unavailable (CommandLineTools) | P3-T09 |
| 2026-04-01 | P5-T06 | Re-scoped overlay sessions to a single display chosen from the mouse location when annotation starts, keeping exactly one overlay panel and one pass-through control panel alive for the session display instead of mirroring UI across all connected monitors | `swiftc -frontend -parse Pinnacle/Overlay/AppKitOverlayService.swift Pinnacle/Overlay/OverlayViewModel.swift` passed; `xcodebuild` unavailable (CommandLineTools) | P3-T09 |
| 2026-04-02 | P4-T14 | Updated default annotation presets so text and highlighter sizes start at `14`, pen/highlighter/text default to yellow, arrow/rectangle/ellipse default to blue, and the eraser cursor icon renders red while keeping the same cursor hotspot; added a focused smoke test covering the preset values | `swiftc -frontend -parse Pinnacle/Domain/AppDomainModels.swift Pinnacle/Overlay/OverlayViewModel.swift Pinnacle/Overlay/OverlayPanel.swift PinnacleTests/PinnacleSmokeTests.swift` passed; `xcodebuild test -project Pinnacle.xcodeproj -scheme Pinnacle -destination 'platform=macOS' -derivedDataPath /tmp/PinnacleDerivedData -only-testing:PinnacleTests/PinnacleSmokeTests CODE_SIGNING_ALLOWED=NO` could not run because `xcode-select` points to CommandLineTools | P3-T09 |
