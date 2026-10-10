import SwiftUI
import UserNotifications

struct AlertSettingsView: View {
    @Environment(\.pivotAccent) private var accent
    @EnvironmentObject private var store: DashboardStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
              VStack(alignment: .leading, spacing: 18) {
                ZStack {
                    Circle()
                        .fill(store.alertsEnabled ? Color.pivotMint.opacity(0.16) : Color.pivotSurfaceRaised)
                    Image(systemName: store.alertsEnabled ? "bell.badge.fill" : "bell")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(store.alertsEnabled ? Color.pivotMint : Color.pivotMuted)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 8) {
                    Text(store.alertsEnabled ? "Ride alerts are on" : "Ride alerts are off")
                        .font(.title2.weight(.bold))
                    Text("PIVOT can notify this iPhone when a reviewed ride or queued attraction closes or reopens at the one park you select.")
                        .foregroundStyle(Color.pivotMuted)
                        .font(.subheadline)
                }

                HStack(spacing: 12) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.selectedPark?.name ?? "No park selected")
                            .font(.headline)
                        Text(store.selectedPark == nil ? "Monitoring and alerts are paused" : "Only this park can trigger alerts")
                            .font(.caption)
                            .foregroundStyle(Color.pivotMuted)
                    }
                    Spacer()
                }
                .pivotCard(padding: 15)

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Live Reopen Radar")
                            .font(.headline)
                        Text(store.selectedPark == nil
                             ? "Choose a park to use the Lock Screen and Notification Center Live Activity."
                             : "The most popular closed ride appears in your Lock Screen and Notification Center Live Activity. Open it for the closure timer and reopening forecast. This does not require notification permission.")
                            .font(.caption)
                            .foregroundStyle(Color.pivotMuted)
                    }
                    Spacer()
                }
                .pivotCard(padding: 15)

                if store.notificationService.authorizationStatus == .denied {
                    Label("Notifications are blocked. Enable PIVOT in iPhone Settings → Notifications.", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .pivotCard(padding: 14)
                }

                if store.selectedPark == nil {
                    Text("Choose a park before turning on ride alerts.")
                        .font(.subheadline)
                        .foregroundStyle(Color.pivotMuted)
                } else if store.alertsEnabled {
                    Button(role: .destructive) {
                        store.disableAlerts()
                    } label: {
                        Label("Turn off ride alerts", systemImage: "bell.slash")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        Task { await store.enableAlerts() }
                    } label: {
                        Label("Turn on ride alerts", systemImage: "bell.badge")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .foregroundStyle(Color.pivotBackground)
                }

                Text("The app checks every 5 seconds while open and refreshes when it returns to the foreground. The Live Activity’s closure timer keeps moving on its own, but ride status is marked paused when its last update becomes stale. Truly real-time background status changes require a future server push service.")
                    .font(.caption)
                    .foregroundStyle(Color.pivotMuted)
                    .fixedSize(horizontal: false, vertical: true)
              }
              .padding(20)
            }
            .background(Color.pivotBackground.ignoresSafeArea())
            .navigationTitle("Ride status alerts")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
