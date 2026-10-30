import SwiftUI
import UserNotifications

struct AlertSettingsView: View {
    @Environment(\.pivotAccent) private var accent
    @EnvironmentObject private var store: DashboardStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Park", value: store.selectedPark?.name ?? "No park selected")
                    LabeledContent("Ride alerts", value: store.alertsEnabled ? "On" : "Off")
                    if store.selectedPark == nil {
                        Text("Choose a park before turning on ride alerts.").foregroundStyle(.secondary)
                    } else if store.alertsEnabled {
                        Button("Turn off ride alerts", role: .destructive) { store.disableAlerts() }
                    } else {
                        Button("Turn on ride alerts") { Task { await store.enableAlerts() } }
                            .disabled(store.isRequestingAlertPermission)
                    }
                    if store.notificationService.authorizationStatus == .denied {
                        Label("Notifications are blocked. Enable PIVOT in iPhone Settings → Notifications.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                } footer: {
                    Text("Alerts only use the park you select while PIVOT is open. Monitoring and alerts pause when no park is selected.")
                }
                Section {
                    Toggle("Favorites only", isOn: preferenceBinding(\.favoritesOnly))
                        .accessibilityIdentifier("Alerts favorites only")
                    if store.alertPreferences.favoritesOnly {
                        Text(store.favoriteRideIDsForSelectedPark.isEmpty
                             ? "No favorites selected for this park. Add rides in Plan to receive favorite-only alerts."
                             : "Uses the same favorite rides you chose in Plan for this park.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Picker("Notify me about", selection: preferenceBinding(\.mode)) {
                        ForEach(NativeAlertPreferences.Mode.allCases) { mode in Text(mode.label).tag(mode) }
                    }.accessibilityIdentifier("Alert mode")
                    if store.alertPreferences.mode == .threshold {
                        Stepper(value: preferenceBinding(\.threshold), in: 0...180, step: 5) {
                            Text("At or below \(store.alertPreferences.threshold) min")
                        }.accessibilityIdentifier("Alert wait threshold")
                        Text("Only a new, fresh wait crossing from above your limit triggers an alert. Unknown waits never count as zero.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: { Text("Smart alerts") } footer: {
                    Text("A ride can trigger each alert type once every 15 minutes. First load, park changes, and reconnects stay quiet. Saving preferences does not turn alerts on.")
                }
                Section("Live Reopen Radar") {
                    Text(store.selectedPark == nil
                         ? "Choose a park to use the Lock Screen and Notification Center Live Activity."
                         : "Your selected Radar ride appears in the Lock Screen Live Activity. Automatic chooses the most popular current closure; a pinned ride is used while it is closed. This does not require notification permission.")
                }
                Section("While PIVOT is open") {
                    Text("The app checks every 5 seconds while open and refreshes when it returns to the foreground. The Live Activity’s closure timer keeps moving on its own, but ride status is marked paused when its last update becomes stale. This build does not register for server push, so new ride alerts and Live Activity status updates are not delivered while PIVOT is in the background.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .tint(accent)
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
