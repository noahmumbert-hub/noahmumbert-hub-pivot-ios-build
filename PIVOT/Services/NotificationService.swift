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

    func deliver(
        alerts: [RideChangeAlert],
        park: FloridaPark,
        snapshotFetchedAt: Date
    ) async {
        guard !alerts.isEmpty else { return }
        await refreshAuthorizationStatus()
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else { return }

        for kind in [RideChangeKind.closed, .reopened] {
            let matching = alerts.filter { $0.kind == kind }
            guard !matching.isEmpty else { continue }

            let content = UNMutableNotificationContent()
            let action = kind == .closed ? "closed" : "reopened"
            let bodyAction = kind == .closed ? "closed" : "open again"
            if matching.count == 1, let alert = matching.first {
                content.title = "\(alert.rideName) \(action)"
                content.body = "\(park.name) · PIVOT now confirms this ride is \(bodyAction)."
            } else {
                content.title = "\(matching.count) rides \(action) at \(park.name)"
                let names = matching.prefix(3).map(\.rideName).joined(separator: ", ")
                let remainder = matching.count > 3 ? " and \(matching.count - 3) more" : ""
                content.body = names + remainder
            }
            content.sound = .default

            let timestamp = Int(snapshotFetchedAt.timeIntervalSince1970)
            let identifier = "pivot-\(park.rawValue)-\(kind.rawValue)-\(timestamp)"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            try? await center.add(request)
        }
    }
}
