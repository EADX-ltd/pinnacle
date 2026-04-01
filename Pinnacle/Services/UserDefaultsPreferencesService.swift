import Foundation
import os

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
