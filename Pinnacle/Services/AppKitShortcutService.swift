import AppKit
import Carbon.HIToolbox
import Foundation
import os

@MainActor
final class AppKitShortcutService: ShortcutService {
    private struct HotKeyRegistration {
        let id: UInt32
        let binding: ShortcutBinding
        let command: ShortcutCommandID
        let reference: EventHotKeyRef?
    }

    private var commandByHotKeyID: [UInt32: ShortcutCommandID] = [:]
    private var registrations: [HotKeyRegistration] = []
    private var handler: (@MainActor (ShortcutCommandID) -> Void)?
    private var eventHandlerRef: EventHandlerRef?
    private var nextHotKeyID: UInt32 = 1
    private let logger = Logger(subsystem: "Pinnacle", category: "ShortcutService")

    func register(bindings: [ShortcutBinding], handler: @escaping @MainActor (ShortcutCommandID) -> Void) throws {
        try unregisterAll()
        try ensureHotKeyEventHandlerInstalled()
        for binding in bindings {
            let hotKeyIDValue = nextHotKeyID
            nextHotKeyID = nextHotKeyID &+ 1

            let carbonHotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: hotKeyIDValue)
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(binding.key.carbonKeyCode),
                binding.modifiers.carbonFlags,
                carbonHotKeyID,
                GetApplicationEventTarget(),
                0,
                &reference
            )
            guard status == noErr else {
                // Roll back any successful registrations from this call so we
                // don't leave system-wide hotkeys active without a handler.
                try? unregisterAll()
                throw ShortcutServiceError.hotKeyRegistrationFailed(
                    command: binding.commandID,
                    status: status
                )
            }
            registrations.append(
                HotKeyRegistration(
                    id: hotKeyIDValue,
                    binding: binding,
                    command: binding.commandID,
                    reference: reference
                )
            )
            commandByHotKeyID[hotKeyIDValue] = binding.commandID
        }
        self.handler = handler
    }

    func unregisterAll() throws {
        for registration in registrations {
            if let reference = registration.reference {
                UnregisterEventHotKey(reference)
            }
        }
        registrations.removeAll()
        commandByHotKeyID.removeAll()
        handler = nil
    }

    private func ensureHotKeyEventHandlerInstalled() throws {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { nextHandler, event, userData -> OSStatus in
                appKitHotKeyEventHandler(nextHandler, event, userData)
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        guard status == noErr else {
            throw ShortcutServiceError.hotKeyEventHandlerInstallationFailed(status: status)
        }
    }

    fileprivate func dispatchHotKeyEvent(hotKeyID: UInt32) {
        Task { @MainActor [weak self] in
            guard let self, let command = self.commandByHotKeyID[hotKeyID] else { return }
            self.logger.log("Shortcut triggered: \(command.rawValue, privacy: .public)")
            self.handler?(command)
        }
    }

    private static let hotKeySignature: OSType = 0x504E434C // "PNCL"
}

private enum ShortcutServiceError: LocalizedError {
    case hotKeyEventHandlerInstallationFailed(status: OSStatus)
    case hotKeyRegistrationFailed(command: ShortcutCommandID, status: OSStatus)

    var errorDescription: String? {
        switch self {
        case let .hotKeyEventHandlerInstallationFailed(status):
            return "Failed to install global hotkey event handler (OSStatus \(status))."
        case let .hotKeyRegistrationFailed(command, status):
            return "Failed to register shortcut for \(command.rawValue) (OSStatus \(status))."
        }
    }
}

private func appKitHotKeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return noErr }
    var eventHotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &eventHotKeyID
    )
    guard status == noErr else { return status }
    let service = Unmanaged<AppKitShortcutService>.fromOpaque(userData).takeUnretainedValue()
    service.dispatchHotKeyEvent(hotKeyID: eventHotKeyID.id)
    return noErr
}

private extension ShortcutModifiers {
    var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.control) { flags |= UInt32(controlKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        if contains(.command) { flags |= UInt32(cmdKey) }
        return flags
    }
}

private extension ShortcutKey {
    var carbonKeyCode: Int {
        switch self {
        case .a: return kVK_ANSI_A
        case .r: return kVK_ANSI_R
        case .p: return kVK_ANSI_P
        case .one: return kVK_ANSI_1
        case .two: return kVK_ANSI_2
        case .three: return kVK_ANSI_3
        case .four: return kVK_ANSI_4
        case .five: return kVK_ANSI_5
        case .six: return kVK_ANSI_6
        case .e: return kVK_ANSI_E
        case .z: return kVK_ANSI_Z
        case .c: return kVK_ANSI_C
        case .leftBracket: return kVK_ANSI_LeftBracket
        case .rightBracket: return kVK_ANSI_RightBracket
        case .space: return kVK_Space
        case .backspace: return kVK_Delete
        }
    }
}
