# AGENTS.md

## Project Scope
These instructions apply to the entire repository.

## Project Overview
- App type: SwiftUI app
- Xcode project: `Pinnacle.xcodeproj`
- Main source directory: `Pinnacle/`
- Entry point: `Pinnacle/PinnacleApp.swift`
- Root view: `Pinnacle/ContentView.swift`

## Working Guidelines
- Make focused, minimal changes that match the existing SwiftUI style.
- Preserve the current project structure unless a change clearly requires reorganization.
- Prefer SwiftUI-native solutions over adding new dependencies.
- Keep names idiomatic Swift: PascalCase for types, camelCase for properties and functions.
- Use `#Preview` for SwiftUI previews when editing views.
- Do not modify Xcode user data unless the user explicitly asks.

## Build And Validation
- Open the app with `Pinnacle.xcodeproj` in Xcode.
- Prefer validating changes with an Xcode build or targeted test run when requested.
- If you add assets, keep them inside `Pinnacle/Assets.xcassets`.

## Professional Code Quality Standards
- Write production-grade Swift with clear boundaries between UI, domain, and services.
- Keep public APIs small and explicit; avoid hidden side effects and global mutable state.
- Prefer protocol-driven design for components that touch IO, permissions, recording, or shortcuts.
- Add or update tests for any non-trivial behavior change; do not ship untested critical paths.
- Handle errors explicitly with actionable user-facing messages where failures are expected.
- Keep concurrency safe (`@MainActor` for UI state, no unsafe cross-thread mutations).
- Preserve readability: meaningful names, short functions, and minimal complexity per change.
- Before marking work complete, run relevant build/tests and document what was validated.

## Files To Treat Carefully
- `Pinnacle.xcodeproj/project.pbxproj`: change only when required for project structure or file registration.
- `Pinnacle.xcodeproj/xcuserdata/`: user-specific data; avoid editing.

## Notes For Future Agents
- Keep these instructions aligned with the existing `CLAUDE.md` project context.
- If additional modules or targets are added later, extend this file with target-specific guidance.
- Architecture and rollout plan is defined in `docs/ARCHITECTURE.md`.
- Concrete task board and status tracking live in `docs/IMPLEMENTATION_TASKS.md`.
- When implementing features, execute phases from section `11` in order.
- After each phase, update the checklist in section `11.1` and the decision log in section `13`.
- Enforce mandatory quality gates defined in `docs/ARCHITECTURE.md` section `11.3`.
- Before coding, set exactly one task to `in_progress` in `docs/IMPLEMENTATION_TASKS.md`.
- After coding, mark the task `done` or `blocked` and update `Current Execution State`, `Execution Log`, and `Blockers Log` (if needed).
- Do not keep more than one `in_progress` task in the task board.
