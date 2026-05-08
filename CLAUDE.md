# Pinnacle

## Project Overview
SwiftUI app project created by Zhivko Poroyliev.

## Tech Stack
- **Language**: Swift
- **UI Framework**: SwiftUI
- **Platform**: macOS only (`SDKROOT = macosx`, deployment target 26.4)
- **Xcode Project**: `Pinnacle.xcodeproj`

## Project Structure
```
Pinnacle/
├── Pinnacle.xcodeproj/       # Xcode project
├── Pinnacle/                 # App source
│   ├── PinnacleApp.swift     # @main entry, NSApplicationDelegate
│   ├── ContentView.swift     # Debug-only root view
│   ├── App/                  # AppContainer (DI), AppStore (state machine)
│   ├── Domain/               # Pure models (shortcuts, tools, scene)
│   ├── Overlay/              # AppKit overlay panels, radial HUD, view models
│   ├── Recording/            # ScreenCaptureKit + AVAssetWriter pipeline
│   ├── Services/             # ServiceProtocols + concrete services
│   ├── Settings/             # Settings scene + view
│   └── Assets.xcassets/      # App assets & icons
└── PinnacleTests/            # XCTest target (smoke tests + stub services)
```

The project uses `PBXFileSystemSynchronizedRootGroup`, so files added to `Pinnacle/` or `PinnacleTests/` on disk become target members automatically — no pbxproj edits needed.

## Build & Run
Open `Pinnacle.xcodeproj` in Xcode and run with ⌘R.

## Code Conventions
- SwiftUI views with `#Preview` macros
- Standard Swift naming conventions (camelCase for vars/funcs, PascalCase for types)

## Gotchas
- Floating overlay panels aren't fully active windows; `NSTextField` / `NSTextView` inside them must disable smart features (`allowsEditingTextAttributes`, `allowsCharacterPickerTouchBarItem`, automatic spelling/text/quote/dash/data/link substitution) or you'll hit `ViewBridge` / `RemoteViewService` errors and task-name port crashes.
- `xcodebuild` from the CLI fails with `tool 'xcodebuild' requires Xcode` when `xcode-select -p` returns CommandLineTools. Run `sudo xcode-select -s /Applications/Xcode.app` once, or build from Xcode directly.
- Test stubs (`NoOpShortcutService`, `InMemoryRecordingService`, etc.) live in `PinnacleTests/StubServices.swift` and must NOT be referenced from production code.

## Professional Quality Expectations
- Maintain clear separation of concerns across UI, state, and service layers.
- Favor protocol-based abstractions for components with side effects.
- Validate behavior with focused tests for changed logic.
- Handle failures explicitly and surface actionable error states.
- Keep changes small, readable, and directly tied to the task.

## Architecture Blueprint
- Implementation architecture lives in `docs/ARCHITECTURE.md`.
- Concrete execution tasks live in `docs/IMPLEMENTATION_TASKS.md`.
- Manual GUI-only verification scenarios live in `docs/MANUAL_TEST_GUIDE.md` (run from Xcode, not CLI).
- Sibling agent spec: `AGENTS.md` (overlapping guidance for non-Claude agents; keep aligned).
- Follow phased rollout in section `11. AI Agent Implementation Plan`.
- Keep section `13. Decision Log` updated after each completed phase.
- Apply mandatory quality gates in section `11.3`.
- Keep task status current in `docs/IMPLEMENTATION_TASKS.md` (`todo`, `in_progress`, `done`, `blocked`) with exactly one `in_progress`.
