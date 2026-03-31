import Foundation

protocol ShortcutService {
    func registerDefaults() throws
    func unregisterAll() throws
}

protocol OverlayService {
    func startOverlay()
    func stopOverlay()
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

struct NoOpShortcutService: ShortcutService {
    func registerDefaults() throws {}
    func unregisterAll() throws {}
}

struct NoOpOverlayService: OverlayService {
    func startOverlay() {}
    func stopOverlay() {}
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
            return key.defaultValue
        }
    }

    func setValue<T: Codable>(_ value: T, for key: PreferenceKey<T>) {
        do {
            let data = try JSONEncoder().encode(value)
            defaults.set(data, forKey: key.name)
        } catch {
            assertionFailure("Failed to encode preference for key \(key.name): \(error)")
        }
    }
}
