import Foundation
import os
import AppKit

@MainActor
protocol ShortcutService {
    func register(bindings: [ShortcutBinding], handler: @escaping @MainActor (ShortcutCommandID) -> Void) throws
    func unregisterAll() throws
}

@MainActor
protocol OverlayService {
    func startOverlay()
    func stopOverlay()
    func update(toolState: ToolState)
    func undoLastChange()
    func redoLastChange()
    func clearAll(allowUndo: Bool)
    func setRadialControlVisible(_ isVisible: Bool)
    func setShortcutBindings(_ bindings: [ShortcutBinding])
    func setCommandHandler(_ handler: @escaping @MainActor (OverlayAction) -> Void)
}

enum OverlayAction: Equatable {
    case selectTool(ToolKind)
    case undo
    case redo
    case clearAll
    case cycleColors
    case increaseStroke
    case decreaseStroke
}

@MainActor
protocol RecordingService {
    var isRecording: Bool { get }
    func startRecording() throws
    func stopRecording() throws
}

protocol PermissionService {
    func refreshPermissions() async -> PermissionStatus
}

@MainActor
protocol PreferencesService {
    func value<T: Codable>(for key: PreferenceKey<T>) -> T
    func setValue<T: Codable>(_ value: T, for key: PreferenceKey<T>)
}

enum PermissionStatus: Equatable {
    case granted
    case denied
    case notDetermined
}

struct PreferenceKey<Value: Codable> {
    let name: String
    let defaultValue: Value
}

@MainActor
struct NoOpShortcutService: ShortcutService {
    func register(bindings: [ShortcutBinding], handler: @escaping @MainActor (ShortcutCommandID) -> Void) throws {}
    func unregisterAll() throws {}
}

@MainActor
final class AppKitShortcutService: ShortcutService {
    private struct KeyChord: Hashable {
        let key: ShortcutKey
        let modifiers: ShortcutModifiers
    }

    private var commandByChord: [KeyChord: ShortcutCommandID] = [:]
    private var handler: (@MainActor (ShortcutCommandID) -> Void)?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private let logger = Logger(subsystem: "Pinnacle", category: "ShortcutService")

    func register(bindings: [ShortcutBinding], handler: @escaping @MainActor (ShortcutCommandID) -> Void) throws {
        try unregisterAll()

        var mapped: [KeyChord: ShortcutCommandID] = [:]
        for binding in bindings {
            mapped[KeyChord(key: binding.key, modifiers: binding.modifiers)] = binding.commandID
        }
        commandByChord = mapped
        self.handler = handler
        installMonitors()
    }

    func unregisterAll() throws {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        commandByChord.removeAll()
        handler = nil
    }

    private func installMonitors() {
        guard localMonitor == nil, globalMonitor == nil else {
            return
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else {
                return event
            }
            return self.process(event) ? nil : event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            // Global monitor callback is non-isolated, so hop to MainActor before touching actor-isolated state.
            // This keeps actor safety explicit even though it introduces a small async ordering difference vs local monitor.
            Task { @MainActor in
                _ = self?.process(event)
            }
        }
    }

    private func process(_ event: NSEvent) -> Bool {
        guard let key = ShortcutKey(event: event) else {
            return false
        }

        let modifiers = ShortcutModifiers(eventModifierFlags: event.modifierFlags)
        guard let command = commandByChord[KeyChord(key: key, modifiers: modifiers)] else {
            return false
        }

        logger.log("Shortcut triggered: \(command.rawValue, privacy: .public)")
        handler?(command)
        return true
    }
}

private extension ShortcutModifiers {
    init(eventModifierFlags flags: NSEvent.ModifierFlags) {
        var mapped: ShortcutModifiers = []
        if flags.contains(.control) {
            mapped.insert(.control)
        }
        if flags.contains(.option) {
            mapped.insert(.option)
        }
        if flags.contains(.shift) {
            mapped.insert(.shift)
        }
        if flags.contains(.command) {
            mapped.insert(.command)
        }
        self = mapped
    }
}

private extension ShortcutKey {
    static let deleteKeyCode: UInt16 = 0x33 // kVK_Delete in HIToolbox/Events.h

    init?(event: NSEvent) {
        switch event.keyCode {
        case Self.deleteKeyCode:
            self = .backspace
            return
        default:
            break
        }

        let normalized = (event.charactersIgnoringModifiers ?? "").lowercased()
        switch normalized {
        case "a":
            self = .a
        case "r":
            self = .r
        case "p":
            self = .p
        case "1":
            self = .one
        case "2":
            self = .two
        case "3":
            self = .three
        case "4":
            self = .four
        case "5":
            self = .five
        case "6":
            self = .six
        case "e":
            self = .e
        case "z":
            self = .z
        case "c":
            self = .c
        case "[":
            self = .leftBracket
        case "]":
            self = .rightBracket
        case " ":
            self = .space
        case "\u{7f}":
            self = .backspace
        default:
            return nil
        }
    }
}

@MainActor
struct NoOpOverlayService: OverlayService {
    func startOverlay() {}
    func stopOverlay() {}
    func update(toolState: ToolState) {}
    func undoLastChange() {}
    func redoLastChange() {}
    func clearAll(allowUndo: Bool) {}
    func setRadialControlVisible(_ isVisible: Bool) {}
    func setShortcutBindings(_ bindings: [ShortcutBinding]) {}
    func setCommandHandler(_ handler: @escaping @MainActor (OverlayAction) -> Void) {}
}

@MainActor
final class InMemoryRecordingService: RecordingService {
    private(set) var isRecording = false

    func startRecording() throws {
        isRecording = true
    }

    func stopRecording() throws {
        isRecording = false
    }
}

struct NoOpPermissionService: PermissionService {
    func refreshPermissions() async -> PermissionStatus {
        .notDetermined
    }
}

@MainActor
final class UserDefaultsPreferencesService: PreferencesService {
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "Pinnacle", category: "Preferences")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func value<T: Codable>(for key: PreferenceKey<T>) -> T {
        guard let data = defaults.data(forKey: key.name) else {
            return key.defaultValue
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            logger.error("Failed to decode preference for key \(key.name, privacy: .public): \(String(describing: error), privacy: .public)")
            return key.defaultValue
        }
    }

    func setValue<T: Codable>(_ value: T, for key: PreferenceKey<T>) {
        do {
            let data = try JSONEncoder().encode(value)
            defaults.set(data, forKey: key.name)
        } catch {
            logger.error("Failed to encode preference for key \(key.name, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
}
