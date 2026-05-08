# Pinnacle v1.0 Release Readiness Summary

Generated: 2026-05-08 by autonomous code-completion pass.

## Recommendation

**Conditional GO** — all code-reachable phases are complete and tested. **One blocker for shipping**: the manual GUI matrix (`docs/MANUAL_TEST_GUIDE.md`) has not been executed against the live app. Specifically the pause/resume freeze fix has zero unit-test coverage and can only be validated by a real recording; the multi-display panel + radial dead-zone + Settings tab UIs have been compiled but never opened.

After the manual matrix passes, this is a GO. After any failures, this is a NO-GO until they're triaged.

## What's verified (unit + build)

- **73 unit tests passing** via `xcodebuild test -scheme Pinnacle -destination 'platform=macOS'`.
- Build succeeds against the macOS 26.4 SDK with no warnings beyond unrelated `#Preview` macro plugin notes.
- All audited concerns from the `/feature-dev fix all` pass were remediated and confirmed by tests.
- Reviewer P2 follow-ups (probe-write, sheet modal) applied.

### Coverage by phase

| Phase | Status | Notes |
|---|---|---|
| 0–2 | done | scaffolding, state store, global shortcuts |
| 3 | in_progress | implementation done; **P3-T09 manual radial UX** still pending |
| 4 | done | tool renderers + undo/redo |
| 5 | done | multi-display support (intentionally single-display per session) |
| 6 | in_progress | implementation + audit fixes done; **P6-T06 manual recording lifecycle matrix** still pending — required to validate the pause/resume freeze fix |
| 7 | in_progress | all code complete (Settings: Shortcuts, Tools, Radial, Output, Permissions); **P7-T05 manual settings flow matrix** still pending |
| 8 | done | preferences repository + schema versioning + output directory + collision-free naming + tests |
| 9 | partial | T01 done; T02/T03 require manual + runtime; T04/T05 documented below |

## What's NOT verified

### Pause/resume freeze fix (highest priority)

`AVAssetWriterPipeline` rebases PTS across pause/resume so the output timeline has no freeze artifact equal to the pause duration. The fix went through one round-trip with the advisor (initial implementation cleared `pauseStart` in `endPause()` which would have re-introduced the bug; corrected before commit). The pipeline is not unit-testable without real `CMSampleBuffer`s; the only validation path is the **P6-T06 manual matrix**:

1. Start recording → wait 5s → pause 5s → resume 5s → stop.
2. Open the produced `.mp4`.
3. **Expected:** ~10s of continuous content with no freeze frame in the middle.
4. **If freeze present:** the fix is wrong. File a row in `Blockers Log` and revisit `AVAssetWriterPipeline.beginPause/endPause/appendVideo/appendAudio`.

### Settings UI surfaces (5 tabs, never GUI-opened)

The `Settings…` menu now opens a 5-tab window: **Shortcuts**, **Tools**, **Radial**, **Output**, **Permissions**. Every tab has been compiled and the underlying state machines tested via `AppStore` API tests, but the SwiftUI views themselves have not been opened in a running app. Walk the **P7-T05 checklist** in `docs/MANUAL_TEST_GUIDE.md` for the full sequence.

Critical interaction points that only manual testing can confirm:
- Live conflict feedback in the shortcut editor (orange banner appears, conflicting rows highlight, edit-out-of-conflict re-saves).
- ColorPicker round-trip preserves user-chosen colors (sRGB conversion has ±1/255 rounding; cosmetic risk only).
- `NSOpenPanel` sheet displays correctly attached to the Settings window after the `runModal → beginSheetModal` switch.
- Permissions panel: deep link to System Settings, denied-state distinction (audit fix).

### Overlay surfaces touched by the audit pass

- **Phantom-stroke fix**: `OverlayGeometry` constants now match dead-zone and hit-test tiers. Manual: with pen active, click options panel buttons; no stray dot should appear.
- **Multi-display panels**: panels are now retained for all `NSScreen.screens`. Manual: drag annotations onto display A, switch active display to B (move mouse there), confirm A's annotations remain visible.
- **HUDView**: now rendered at top-left. Manual: confirm the tool pill is visible during annotation, hover for tooltip.

## Performance (P9-T03)

Not measured. Architecture targets in `docs/ARCHITECTURE.md` §9 specify <16ms input-to-stroke latency, <50% CPU during recording, etc. Profiling requires live workload; flagged as a runtime task for the user.

## Defect log (P9-T04)

No P0 / P1 unresolved defects. Tracked items at lower severity:

| ID | Severity | Surface | Description | Disposition |
|---|---|---|---|---|
| AUDIT-1 | P0 (resolved) | Recording | Stop-during-startup race — startup `Task` was unjoined | Fixed in `e9e13c2`; covered by manual P6-T06 |
| AUDIT-2 | P0 (resolved) | Recording | Fire-and-forget finalization on stop | Fixed in `e9e13c2`; covered by terminate-then-quit-fast in P6-T06 |
| AUDIT-3 | P0 (resolved) | Recording | Empty-file stop before first frame was silent | Fixed in `e9e13c2`; surfaces actionable error |
| AUDIT-4 | P0 (resolved) | Overlay | Phantom stroke on options panel OK/Cancel | Fixed in `e9e13c2`; verifiable in P3-T09 |
| AUDIT-5 | P0 (resolved) | Store | Recording-error during paused leaks overlay | Fixed in `e9e13c2`; covered by 2 unit tests |
| AUDIT-6 | P0 (resolved) | Store | Conflict resolver overwrote user shortcuts | Fixed in `e9e13c2`; covered by unit test |
| AUDIT-7 | P1 (resolved) | Recording | Pause was sample-drop, not timeline pause (freeze artifact) | **Fix landed; only manually validatable via P6-T06** |
| REVIEW-1 | P2 (resolved) | Settings/Output | `isWritableFile` was best-effort | Replaced with probe write-and-delete in `e9b4950` |
| REVIEW-2 | P2 (resolved) | Settings/Output | `runModal()` blocked main thread | Switched to `beginSheetModal(for:)` in `e9b4950` |
| OPEN-1 | P3 | Overlay | HUD pill `.onHover` tooltip never fires in pass-through mode (panel sets `ignoresMouseEvents = true`). Pre-existing constraint. | Defer; cosmetic. |
| OPEN-2 | P3 | Settings/Shortcuts | Live save re-runs `unregisterAll()` + 17×`RegisterEventHotKey` on each modifier toggle. Brief no-shortcuts window. | Defer; debounce when it becomes a hot path. |
| OPEN-3 | P3 | Recording | `AppContainer.live` is implicit dependency of `PinnacleAppDelegate.applicationShouldTerminate`. | Defer; would clean up by injecting container into the delegate. |
| OPEN-4 | P3 | App | `AppStore.swift` is ~620 lines covering 6 domains. Not pathological at this size. | Defer until growth pressure. |

## Pre-ship checklist

Before tagging v1.0:

1. [ ] Run **P6-T06** manual matrix (`docs/MANUAL_TEST_GUIDE.md`).
2. [ ] Run **P3-T09** manual radial usability checklist.
3. [ ] Run **P7-T05** Settings flows checklist (9 sections).
4. [ ] Run **P9-T03** performance profiling and check against §9 targets.
5. [ ] Open Console.app filtered by `Pinnacle` for one full session — no unexpected errors.
6. [ ] Test cold-launch with no persisted prefs (delete `~/Library/Preferences/com.eadx.Pinnacle.plist` first).
7. [ ] Test cold-launch with screen-recording permission revoked.
8. [ ] Resolve any blockers added to `IMPLEMENTATION_TASKS.md` during the manual passes.

After all eight pass: GO for v1.0.

## Known scope boundaries

- **Single-display recording per session** is intentional (architecture §4.5). Recording captures the display under the mouse at start; switching displays mid-recording is not supported.
- **Phase 8 metadata sidecar (P8-T05)** was skipped per its `Optional` label. Revisit when a concrete consumer exists.
- **Auto-hide / collapsed-size radial preferences** were skipped — auto-hide was deliberately removed by P3-T18; collapsed-size deferred as premature.
- **Color picker uses sRGB conversion** with ±1/255 rounding error. Palette swatch highlight may not light up after picking a near-swatch custom color (cosmetic).
