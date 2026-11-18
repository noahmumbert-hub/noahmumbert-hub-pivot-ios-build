import Foundation
import Combine
import UserNotifications

@MainActor
final class NotificationService: ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let readAuthorization: () async -> UNAuthorizationStatus
    private let askAuthorization: () async throws -> Bool
    private let submit: (UNNotificationRequest) async throws -> Void

    init(center: UNUserNotificationCenter = .current()) {
        readAuthorization = { await center.notificationSettings().authorizationStatus }
        askAuthorization = { try await center.requestAuthorization(options: [.alert, .sound, .badge]) }
        submit = { try await center.add($0) }
    }

#if DEBUG
    // Exercise the real notification content and submission boundary without changing device permissions.
    init(authorizedForTest: UNAuthorizationStatus, submit: @escaping (UNNotificationRequest) async throws -> Void) {
        self.readAuthorization = { authorizedForTest }
        self.askAuthorization = { false }
        self.submit = submit
    }

#endif

    func refreshAuthorizationStatus() async {
        authorizationStatus = await readAuthorization()
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await askAuthorization()
            await refreshAuthorizationStatus()
            return granted
        } catch {
            await refreshAuthorizationStatus()
            return false
        }
    }

    /// Local delivery only. No APNs registration or background capability is
    /// implied by enabling these foreground snapshot alerts.
    func deliver(
        alerts: [NativeSmartAlert],
        park: FloridaPark,
        shouldDeliver: @MainActor (NativeSmartAlert) -> Bool
    ) async -> [NativeSmartAlert] {
        guard !alerts.isEmpty else { return [] }
        await refreshAuthorizationStatus()
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else { return [] }
        var delivered: [NativeSmartAlert] = []
        for alert in alerts {
            guard shouldDeliver(alert) else { continue }
            guard alert.parkId == park.rawValue else { continue }
            let content = UNMutableNotificationContent()
            content.title = alert.summary
            switch alert.kind {
            case .closed:
                content.body = "\(park.name) · PIVOT now confirms this ride is closed."
            case .reopened:
                content.body = "\(park.name) · PIVOT now confirms this ride is open again."
            case .waitBelow:
                guard let wait = alert.waitTime else { continue }
                content.body = "\(park.name) · The posted wait dropped to \(wait) min, within your alert limit."
            }
            content.sound = .default
            content.userInfo = ["parkId": alert.parkId, "rideId": alert.rideId, "kind": alert.kind.rawValue]
            // Stable per-ride event IDs and a persisted 15-minute cooldown
            // protect against duplicate snapshots and repeated status flaps.
            let request = UNNotificationRequest(identifier: alert.eventIdentifier, content: content, trigger: nil)
            do {
                try await submit(request)
                delivered.append(alert)
            } catch {
                // Never report failed notification submissions as delivered.
                continue
            }
        }
        return delivered
    }
}
