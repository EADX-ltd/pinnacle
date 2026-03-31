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
| Current Task ID | `none` |
| Current Phase | `none` |
| Last Updated (UTC) | `YYYY-MM-DD HH:MM` |
| Updated By | `agent` |

## Phase Status Board

| Phase | Name | Status | Exit Criteria |
|---|---|---|---|
| 0 | Project scaffolding and protocols | `todo` | Task group `P0-*` all `done` |
| 1 | Menu bar app shell and state store | `todo` | Task group `P1-*` all `done` |
| 2 | Global shortcuts | `todo` | Task group `P2-*` all `done` |
| 3 | Overlay engine (single display) | `todo` | Task group `P3-*` all `done` |
| 4 | Tool renderers + undo/redo | `todo` | Task group `P4-*` all `done` |
| 5 | Multi-display support | `todo` | Task group `P5-*` all `done` |
| 6 | Recording engine integration | `todo` | Task group `P6-*` all `done` |
| 7 | Settings UI for shortcuts/colors | `todo` | Task group `P7-*` all `done` |
| 8 | Persistence and output management | `todo` | Task group `P8-*` all `done` |
| 9 | Stabilization, profiling, test pass | `todo` | Task group `P9-*` all `done` |

## Concrete Task Backlog

### Phase 0: Project Scaffolding and Protocols
| ID | Task | Depends On | Status | Acceptance Criteria |
|---|---|---|---|---|
| P0-T01 | Create source folders: `App`, `Domain`, `Services`, `Overlay`, `Recording`, `Settings` | none | `todo` | Folders exist and compile references resolve |
| P0-T02 | Define protocol contracts: `ShortcutService`, `OverlayService`, `RecordingService`, `PermissionService`, `PreferencesService` | P0-T01 | `todo` | Protocols compile with clear method signatures |
| P0-T03 | Implement DI container for protocol-backed services | P0-T02 | `todo` | App startup resolves service graph without crashes |
| P0-T04 | Add base smoke test target wiring for domain/services | P0-T02 | `todo` | At least one passing smoke test in CI/local |
| P0-T05 | Document module boundaries in code comments/readme header | P0-T01 | `todo` | Boundaries are explicit for future contributors |

### Phase 1: Menu Bar Shell and State Store
| ID | Task | Depends On | Status | Acceptance Criteria |
|---|---|---|---|---|
| P1-T01 | Add `MenuBarExtra` scene with start/stop actions | P0-T03 | `todo` | Menu bar controls render and dispatch commands |
| P1-T02 | Implement `AppStore` with `SessionMode` and `ToolState` | P0-T03 | `todo` | Central observable state drives UI and engines |
| P1-T03 | Add command dispatch enum and reducer/handler layer | P1-T02 | `todo` | Commands route deterministically to state/services |
| P1-T04 | Add unit tests for core state transitions | P1-T02 | `todo` | Tests cover idle/annotating/recording transitions |
| P1-T05 | Add menu bar status indicator for active mode | P1-T01 | `todo` | Indicator reflects real-time session state |

### Phase 2: Global Shortcuts
| ID | Task | Depends On | Status | Acceptance Criteria |
|---|---|---|---|---|
| P2-T01 | Implement platform shortcut provider adapter | P0-T02 | `todo` | Global registration/unregistration works reliably |
| P2-T02 | Wire default keymap from architecture section 5.3 | P2-T01 | `todo` | All default bindings trigger correct commands |
| P2-T03 | Add shortcut conflict validator and fallback handling | P2-T02 | `todo` | Conflicts are detected and blocked in UI/store |
| P2-T04 | Persist and restore shortcut bindings | P2-T02, P8-T01 | `todo` | Restart preserves user bindings |
| P2-T05 | Add tests for shortcut command mapping | P2-T02 | `todo` | Mapping tests pass for tool + lifecycle commands |

### Phase 3: Overlay Engine (Single Display)
| ID | Task | Depends On | Status | Acceptance Criteria |
|---|---|---|---|---|
| P3-T01 | Create transparent top-level overlay window manager | P1-T03 | `todo` | Overlay can be shown/hidden without focus issues |
| P3-T02 | Capture pointer input and route events to active tool | P3-T01 | `todo` | Pointer down/move/up stream received correctly |
| P3-T03 | Implement pen renderer with vector path model | P3-T02 | `todo` | Pen strokes render smoothly and persist in scene |
| P3-T04 | Add annotation HUD showing active tool/color | P1-T05 | `todo` | HUD updates instantly on tool change |
| P3-T05 | Measure and record baseline draw latency | P3-T03 | `todo` | Latency report logged against <16ms target |
| P3-T06 | Implement radial on-screen control shell (single-circle collapsed + expanded states) | P3-T01 | `todo` | Control appears as small collapsed circle by default, expands/collapses correctly, and remains draggable |
| P3-T07 | Wire radial selections to tool/color/stroke commands | P3-T06, P1-T03 | `todo` | Radial picks immediately update active tool state and renderer behavior |
| P3-T08 | Enforce pointer pass-through outside radial hit area | P3-T06, P3-T02 | `todo` | Drawing interactions are unaffected outside radial control bounds |
| P3-T09 | Add radial usability checks (auto-hide, edge snap, no lag) | P3-T06, P3-T07 | `todo` | Manual checklist confirms non-blocking behavior and smooth interaction |
| P3-T10 | Add radial quick actions (undo, redo, clear) | P4-T05, P4-T06, P3-T06 | `todo` | Quick actions execute through command dispatcher and reflect state immediately |
| P3-T11 | Add hover tooltips on HUD/radial items with mapped key bindings | P2-T02, P3-T06 | `todo` | On hover, tooltip shows command label + current binding and updates after remap |
| P3-T12 | Enforce annotation-mode visibility rules for radial control | P1-T02, P3-T06 | `todo` | Control appears/hides according to session mode contract without stale overlays |
| P3-T13 | Implement hover-triggered expand and leave-triggered collapse delay | P3-T06 | `todo` | Hover expands reliably; pointer leave collapses after delay without flicker or accidental toggles |
| P3-T14 | Implement click-to-pin expanded mode toggle | P3-T06, P3-T13 | `todo` | First click pins expanded state; second click unpins and restores hover-driven collapse |

### Phase 4: Tool Renderers and Undo/Redo
| ID | Task | Depends On | Status | Acceptance Criteria |
|---|---|---|---|---|
| P4-T01 | Implement highlighter renderer with alpha behavior | P3-T03 | `todo` | Highlighter appears translucent and smooth |
| P4-T02 | Implement arrow/rectangle/ellipse renderers | P3-T03 | `todo` | Shape tools support drag preview and final commit |
| P4-T03 | Implement text placement and editing commit flow | P3-T02 | `todo` | Text tool creates editable then committed text nodes |
| P4-T04 | Implement eraser object-hit removal logic | P4-T02, P4-T03 | `todo` | Eraser removes targeted scene elements only |
| P4-T05 | Implement undo/redo command stack | P4-T01, P4-T02, P4-T03, P4-T04 | `todo` | Undo/redo works across all tool element types |
| P4-T06 | Implement clear-all command + confirmation behavior | P4-T05 | `todo` | Scene clears safely and operation is undoable if intended |
| P4-T07 | Add renderer + undo/redo tests | P4-T05 | `todo` | Tests cover mixed tool history operations |

### Phase 5: Multi-Display Support
| ID | Task | Depends On | Status | Acceptance Criteria |
|---|---|---|---|---|
| P5-T01 | Add display discovery and lifecycle observer | P3-T01 | `todo` | Attach/detach display updates overlays correctly |
| P5-T02 | Create one overlay per active display | P5-T01 | `todo` | Annotation available independently on each display |
| P5-T03 | Implement coordinate transform utility | P5-T02 | `todo` | Cross-display geometry calculations are correct |
| P5-T04 | Ensure tool parity and state sync across displays | P5-T02 | `todo` | Same tool/color behavior on all displays |
| P5-T05 | Add tests/manual matrix for edge display layouts | P5-T03 | `todo` | Cases include negative origins and mixed scale factors |

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
| P7-T06 | Add radial control preferences (enabled, collapsed size, hover-expand delay, auto-hide, default position, click-pin enabled) | P3-T06, P3-T13, P3-T14 | `todo` | Users can configure radial behavior from Settings |
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
| P9-T02 | Execute manual test matrix for permissions/displays/recording/radial UX | P5-T05, P6-T06, P7-T05, P3-T09, P3-T10, P3-T11, P3-T13, P3-T14 | `todo` | Matrix completed and documented |
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

## Execution Log
| Date | Task ID | Change Summary | Validation | Next Task |
|---|---|---|---|---|
| YYYY-MM-DD | P?-T?? | TBD | TBD | TBD |
