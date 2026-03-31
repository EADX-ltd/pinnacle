# Pinnacle

## Project Overview
SwiftUI app project created by Zhivko Poroyliev.

## Tech Stack
- **Language**: Swift
- **UI Framework**: SwiftUI
- **Platform**: iOS/macOS
- **Xcode Project**: `Pinnacle.xcodeproj`

## Project Structure
```
Pinnacle/
├── Pinnacle.xcodeproj/       # Xcode project
└── Pinnacle/                 # App source
    ├── PinnacleApp.swift     # App entry point (@main)
    ├── ContentView.swift     # Root view
    └── Assets.xcassets/      # App assets & icons
```

## Build & Run
Open `Pinnacle.xcodeproj` in Xcode and run with ⌘R.

## Code Conventions
- SwiftUI views with `#Preview` macros
- Standard Swift naming conventions (camelCase for vars/funcs, PascalCase for types)

## Professional Quality Expectations
- Maintain clear separation of concerns across UI, state, and service layers.
- Favor protocol-based abstractions for components with side effects.
- Validate behavior with focused tests for changed logic.
- Handle failures explicitly and surface actionable error states.
- Keep changes small, readable, and directly tied to the task.

## Architecture Blueprint
- Implementation architecture lives in `docs/ARCHITECTURE.md`.
- Concrete execution tasks live in `docs/IMPLEMENTATION_TASKS.md`.
- Follow phased rollout in section `11. AI Agent Implementation Plan`.
- Keep section `13. Decision Log` updated after each completed phase.
- Apply mandatory quality gates in section `11.3`.
- Keep task status current in `docs/IMPLEMENTATION_TASKS.md` (`todo`, `in_progress`, `done`, `blocked`) with exactly one `in_progress`.
