# Pinnacle Manual Test Guide

Step-by-step manual checks for the two open GUI-only tasks:

- **P3-T09** — radial usability checks (auto-hide, edge snap, no lag)
- **P6-T06** — recording lifecycle scenario matrix

Run from a full Xcode/macOS session (not CLI). Build & run with `⌘R` from `Pinnacle.xcodeproj`. The app lives in the menu bar (pencil icon).

---

## Pre-flight

1. Quit any prior run of Pinnacle.
2. In **System Settings → Privacy & Security → Screen Recording**, remove Pinnacle's entry if present (so the TCC prompt re-appears on first use).
3. Build & run from Xcode. Confirm the menu bar pencil icon appears.
4. Open Console.app and filter by `Pinnacle` to capture any runtime errors.

---

## P3-T09 — Radial Usability Checklist

Acceptance: radial control behaves smoothly and never blocks underlying app interactions.

### 1. First-launch placement
1. Click the menu bar icon → **Start Annotating** (or press the toggle-annotation shortcut).
2. **Expected:** overlay activates on the display under the mouse; radial control HUD appears on the right side of that display.
3. **Pass criteria:** HUD appears within ~200 ms; no flicker; no overlay on other displays.

### 2. Hover activation & permanent expansion
1. Hover the collapsed center circle.
2. **Expected:** ring expands to show all tools; tool tooltips appear on hover.
3. Move the mouse far from the radial for >5 seconds.
4. **Expected:** ring stays expanded (auto-collapse was removed in P3-T18). It does **not** dismiss itself.

### 3. Drag relocation
1. Drag the radial center to a different screen position.
2. **Expected:** smooth follow without lag; no duplicate ring; releases at drop point.
3. Drag toward each screen edge in turn (top, bottom, left, right).
4. **Expected:** radial stays visible — clamps inside the display bounds rather than disappearing off-screen.

### 4. Tool selection & options panel
1. Click each tool in the ring (pen, highlighter, arrow, rectangle, ellipse, text, eraser).
2. **Expected:** clicked tool becomes active; HUD reflects active tool; for configurable tools (pen, highlighter, arrow, rectangle, ellipse, text), the center icon swaps to a paintpalette/options trigger.
3. Click the center palette icon.
4. **Expected:** options panel appears anchored below the ring with `OK` / `Cancel` and a red close button (top-right).
5. Change a setting (e.g., color or stroke), click `OK`.
6. **Expected:** subsequent strokes use the new setting.
7. Open options again, change something, click `Cancel` (or red close).
8. **Expected:** changes discarded.

### 5. Pass-through mode (Escape contract)
1. With options panel open, press `Escape`.
2. **Expected:** options close; tool stays selected.
3. Start typing a text annotation, then press `Escape` mid-draft.
4. **Expected:** text draft cancels; tool stays selected.
5. Press `Escape` again with no draft/options open.
6. **Expected:** tool deselects and the overlay enters **pass-through mode** — only the small radial center remains; clicks elsewhere reach underlying apps.

### 6. Pass-through reach-through
1. While in pass-through, click into a Finder window or browser behind the overlay.
2. **Expected:** the underlying app receives the click (selects icon, follows link, etc.); overlay is non-blocking outside the radial center.
3. Click the small radial center button.
4. **Expected:** pass-through exits, overlay returns, but no tool is preselected (P3-T24 contract).

### 7. Tool shortcuts from pass-through
1. Re-enter pass-through (Escape twice from a clean state).
2. Press a tool shortcut (e.g., `P` for pen — confirm in Settings if remapped).
3. **Expected:** pass-through exits, ring expands, that tool becomes active immediately (P4-T15 contract).

### 8. Multi-display behavior
*Skip if you have only one display.*
1. With overlay active on display A, move the cursor to display B and trigger annotation toggle.
2. **Expected:** the **same** session stays bound to display A (P5-T06 single-display session contract). Overlay does not flash onto B.
3. Stop annotation, move cursor to B, start annotation again.
4. **Expected:** new session activates on display B only.

### 9. Performance / latency
1. With pen selected, draw quickly across the display in long curves.
2. **Expected:** no visible stroke lag (target <16 ms per architecture §9). Strokes track the cursor without trailing.
3. Watch Activity Monitor → Pinnacle CPU.
4. **Expected:** idle ~0–2%, while drawing ≤ ~30% on a single performance core.

### 10. Quick actions (undo / redo / clear)
1. Draw three distinct elements (e.g., pen stroke, rectangle, text).
2. Trigger **undo** (shortcut or radial action) three times.
3. **Expected:** elements removed in reverse order with no flicker.
4. Trigger **redo** three times.
5. **Expected:** elements restored in original order.
6. Trigger **clear all** while elements present.
7. **Expected:** scene clears; subsequent **undo** restores them (clear is undoable per P4-T06).

**Recording results:** any failed step → file under `Blockers Log` in `docs/IMPLEMENTATION_TASKS.md` keyed to `P3-T09`.

---

## P6-T06 — Recording Lifecycle Scenario Matrix

Acceptance: start/stop/pause/resume work reliably, output MP4 is valid, errors recover gracefully.

### Pre-conditions
- Pinnacle has Screen Recording permission (granted in pre-flight).
- `~/Movies/Pinnacle/` is empty or you've noted current contents.

### 1. First-time TCC permission flow
*Run only on a fresh Pinnacle install or after revoking Screen Recording permission.*
1. With permission **revoked**, click menu bar → **Start Recording**.
2. **Expected:** macOS Screen Recording permission prompt appears; an error toast/log line indicates "permission required".
3. Approve in System Settings, **fully quit** Pinnacle, relaunch.
4. Try **Start Recording** again.
5. **Expected:** capture starts without a prompt.

### 2. Basic record → stop, no audio
1. Confirm `capturesSystemAudio` is **off** (default).
2. **Start Recording** from the menu bar.
3. Verify menu bar icon switches to `record.circle`.
4. Wait ~10 seconds while doing visible activity (move windows, type).
5. **Stop Recording**.
6. **Expected output:**
   - File appears at `~/Movies/Pinnacle/Pinnacle-yyyyMMdd-HHmmss.mp4`.
   - File size > 0 bytes.
   - Open in QuickTime → video plays end-to-end at ~30 fps; no audio track.
   - File duration ≈ recording wall-clock time (±1 s).

### 3. Record with overlay annotations (Option A capture)
1. Start recording.
2. Toggle annotation on, draw pen strokes, create a text element.
3. Stop recording.
4. **Expected:** the resulting MP4 shows the overlay annotations baked into the video (architecture §4.5 Option A).

### 4. Pause / Resume
1. Start recording.
2. After ~5 s, trigger **Pause** (shortcut or menu).
3. **Expected:** menu bar icon switches to `pause.circle.fill`.
4. Wait ~5 s; do visible work that should **not** appear in the file.
5. Trigger **Resume**.
6. **Expected:** icon returns to `record.circle.fill` (or `record.circle` depending on annotation state).
7. After ~5 s more, **Stop**.
8. **Expected output:** MP4 plays as one continuous video — paused interval is **omitted**, not blank-frames-padded. Total duration ≈ 10 s, not 15 s.

### 5. Stop while paused
1. Start → after 5 s, **Pause** → after 3 s, **Stop** (skipping resume).
2. **Expected:** file finalizes cleanly (~5 s duration); session returns to idle (or back to annotating if you were annotating).

### 6. Idempotent commands
1. With recording active, send **Start** again (e.g., re-trigger toggle quickly).
2. **Expected:** no second file created; no crash; session stays in `recording`.
3. Stop, then send **Stop** again immediately.
4. **Expected:** no error toast; session stays `idle`.

### 7. Audio capture toggle
1. Open Settings (or whatever toggle UI exists; otherwise toggle `capturesSystemAudio` from a debug entry point).
2. Enable **Capture system audio**.
3. Play music or a video with sound.
4. Start recording → ~10 s → Stop.
5. **Expected:** MP4 has an AAC audio track audible in QuickTime; lip-sync is reasonable.
6. Disable the toggle, record again.
7. **Expected:** new file has no audio track.

### 8. Recording while annotating, mode transitions
1. Toggle annotation **on** → session = `annotating`.
2. Start recording → session = `recordingAndAnnotating` (icon `record.circle.fill`).
3. Toggle annotation off → session = `recording` (icon `record.circle`).
4. Toggle annotation back on → session = `recordingAndAnnotating`.
5. Stop recording → session = `annotating` (overlay still active).
6. Toggle annotation off → session = `idle`.
7. **Expected:** every transition matches the table above; output MP4 captures both the annotating and non-annotating phases continuously.

### 9. Display selection
*If you have multiple displays.*
1. Place cursor on display A, **Start Recording**.
2. Move work between displays.
3. Stop, inspect MP4.
4. **Expected:** MP4 dimensions match display A's pixel size; only display A's contents are recorded for the entire session, regardless of where the cursor went.

### 10. Error recovery — permission revoked mid-session
1. Start a recording.
2. In System Settings, **revoke** Screen Recording permission while the recording is active. (macOS may force-quit the stream.)
3. **Expected:**
   - Pinnacle's `lastErrorMessage` shows a recording failure.
   - Session resets: `recording` → `idle`, `recordingAndAnnotating` → `annotating`.
   - Menu bar icon returns to non-recording state.
   - Subsequent **Start Recording** prompts/throws permission required again.

### 11. Error recovery — disk pressure
*Optional / advanced.* Fill `~/Movies/Pinnacle/` parent volume to <10 MB free, then try to record. Verify the failure surfaces via `lastErrorMessage` instead of crashing.

### 12. File integrity sweep
After completing the above, for each generated MP4:
1. Open in QuickTime → confirms decodes.
2. Run `mdls -name kMDItemDurationSeconds <file>` → non-zero, matches expected duration.
3. (Optional) `ffprobe <file>` → verify H.264 video codec, AAC audio codec when audio was on.

---

## Reporting

For each task, record the date and a single line per scenario:

```
P3-T09 / 2026-MM-DD
  1. ✅ first-launch placement
  2. ✅ hover activation
  3. ❌ drag relocation — radial disappears off right edge of laptop display (notes...)
  ...
```

If all scenarios pass, mark the task `done` in `docs/IMPLEMENTATION_TASKS.md` and append an entry to section 13 of `docs/ARCHITECTURE.md`.

If any scenario fails, set status to `blocked` and add an entry under **Blockers Log** in `docs/IMPLEMENTATION_TASKS.md`.
