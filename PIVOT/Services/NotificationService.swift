import Foundation
import Combine
import UserNotifications

@MainActor
final class NotificationService: ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func refreshAuthorizationStatus() async {
        authorizationStatus = await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
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
                try await center.add(request)
                delivered.append(alert)
            } catch {
                // Never report failed notification submissions as delivered.
                continue
            }
        }
        return delivered
    }
}
