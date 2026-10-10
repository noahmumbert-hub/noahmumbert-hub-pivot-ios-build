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
                    Text("Choose which changes should notify this iPhone while PIVOT is open. Alerts only use the park you select.")
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

                VStack(alignment: .leading, spacing: 14) {
                    Text("Smart alerts")
                        .font(.headline)
                    Toggle("Favorites only", isOn: preferenceBinding(\.favoritesOnly))
                        .tint(accent)
                        .accessibilityIdentifier("Alerts favorites only")
                    if store.alertPreferences.favoritesOnly {
                        Text(store.favoriteRideIDsForSelectedPark.isEmpty
                             ? "No favorites selected for this park. Add rides in Plan to receive favorite-only alerts."
                             : "Uses the same favorite rides you chose in Plan for this park.")
                            .font(.caption)
                            .foregroundStyle(Color.pivotMuted)
                    }
                    Picker("Notify me about", selection: preferenceBinding(\.mode)) {
                        ForEach(NativeAlertPreferences.Mode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .accessibilityIdentifier("Alert mode")
                    if store.alertPreferences.mode == .threshold {
                        Stepper(value: preferenceBinding(\.threshold), in: 0...180, step: 5) {
                            Text("At or below \(store.alertPreferences.threshold) min")
                        }
                        .accessibilityIdentifier("Alert wait threshold")
                        Text("Only a new, fresh wait crossing from above your limit triggers an alert. Unknown waits never count as zero.")
                            .font(.caption)
                            .foregroundStyle(Color.pivotMuted)
                    }
                    Text("A ride can trigger each alert type once every 15 minutes. First load, park changes, and reconnects stay quiet. Saving preferences does not turn alerts on.")
                        .font(.caption)
                        .foregroundStyle(Color.pivotMuted)
                        .fixedSize(horizontal: false, vertical: true)
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
                             : "Your selected Radar ride appears in the Lock Screen Live Activity. Automatic chooses the most popular current closure; a pinned ride is used while it is closed. This does not require notification permission.")
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
                    .disabled(store.isRequestingAlertPermission)
                    .tint(accent)
                    .foregroundStyle(Color.pivotBackground)
                }

                Text("The app checks every 5 seconds while open and refreshes when it returns to the foreground. The Live Activity’s closure timer keeps moving on its own, but ride status is marked paused when its last update becomes stale. This build does not register for server push, so new ride alerts and Live Activity status updates are not delivered while PIVOT is in the background.")
                    .font(.caption)
                    .foregroundStyle(Color.pivotMuted)
                    .fixedSize(horizontal: false, vertical: true)
              }
              .padding(20)
            }
            .background(Color.pivotBackground.ignoresSafeArea())
            .navigationTitle("Smart ride alerts")
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
    private func preferenceBinding<Value>(_ keyPath: WritableKeyPath<NativeAlertPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { store.alertPreferences[keyPath: keyPath] },
            set: { value in
                var next = store.alertPreferences
                next[keyPath: keyPath] = value
                store.updateAlertPreferences(next)
            }
        )
    }
}
