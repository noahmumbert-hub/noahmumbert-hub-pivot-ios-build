import Foundation

/// Local notification preferences. Saving these values never requests permission,
/// registers an APNs token, or changes whether delivery is enabled.
struct NativeAlertPreferences: Codable, Equatable, Sendable {
    enum Mode: String, Codable, CaseIterable, Identifiable, Sendable {
        case all
        case reopened
        case threshold

        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: "Closures and reopenings"
            case .reopened: "Reopenings only"
            case .threshold: "Wait drops to my limit"
            }
        }
    }

    static let storageKey = "pivot.smartAlerts.v1"
    static let cooldownMinutes = 15
    static let `default` = NativeAlertPreferences()

    var favoritesOnly = false
    var mode: Mode = .all
    var threshold = 20

    var normalized: NativeAlertPreferences {
        var value = self
        if !(0...180).contains(value.threshold) { value.threshold = 20 }
        return value
    }

    static func load(from defaults: UserDefaults) -> NativeAlertPreferences {
        guard let data = defaults.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode(Self.self, from: data) else { return .default }
        return stored.normalized
    }

    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(normalized) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
