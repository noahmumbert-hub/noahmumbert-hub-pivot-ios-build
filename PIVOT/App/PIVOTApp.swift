import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if DEBUG && canImport(UIKit)
import Combine
import OSLog
#endif
import UserNotifications

@main
struct PIVOTApp: App {
#if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
#endif
    @StateObject private var store = DashboardStore()
    @AppStorage(PivotAccent.storageKey) private var selectedAccent = PivotAccent.mint.rawValue
    @AppStorage("pivot:appearance") private var appearance = "dark"
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            appContent
                .environmentObject(store)
                .environment(\.pivotAccent, PivotAccent.resolve(selectedAccent).color)
                .tint(PivotAccent.resolve(selectedAccent).color)
                .preferredColorScheme(testColorScheme)
                .modifier(PivotUITestTypeSize())
                .onChange(of: selectedAccent) { _, _ in
                    store.synchronizeLiveActivity()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { Task { await RideArtworkDownloads.shared.pause() } }
                }
        }
    }

    private var testColorScheme: ColorScheme? {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-dark") { return .dark }
        if ProcessInfo.processInfo.arguments.contains("--ui-light") { return .light }
#endif
        switch appearance {
        case "light": return .light
        case "system": return nil
        default: return .dark
        }
    }

    @ViewBuilder
    private var appContent: some View {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--park-map-ui-test") {
            NativeParkMapUITestScreen()
        } else if ProcessInfo.processInfo.arguments.contains("--wait-forecast-ui-test") {
            NativeWaitForecastUITestScreen()
        } else if ProcessInfo.processInfo.arguments.contains("--hhn-ui-test") {
            NativeHorrorNightUITestScreen()
#if canImport(UIKit)
        } else if ProcessInfo.processInfo.arguments.contains("--ride-search-cold-control") {
            RideSearchColdControlScreen()
#endif
        } else {
            RootView()
                .overlay(alignment: .topLeading) {
                    if ProcessInfo.processInfo.arguments.contains("--map-refresh-diagnostics") {
                        // A test-only AX value exposes the actual request outcome
                        // without adding a control or changing the visible Map.
                        Text("Map refresh request diagnostic").font(.system(size: 1))
                            .frame(width: 1, height: 1).opacity(0.02)
                            .accessibilityIdentifier("Map refresh request diagnostic")
                            .accessibilityValue(store.mapRefreshDiagnostic)
                            .allowsHitTesting(false)
                    }
                }
        }
#else
        RootView()
#endif
    }
}

#if DEBUG && canImport(UIKit)
// A diagnostic-only first-keyboard control. It keeps Ride search's native
// TextField, traits and row geometry while removing the surrounding app work.
private struct RideSearchColdControlScreen: View {
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    private static let timingLog = Logger(subsystem: "com.noahmumbert.PIVOT",
                                          category: "ride-search-timing")
    private static let nativeEditingObserver: NSObjectProtocol = NotificationCenter.default.addObserver(
        forName: UITextField.textDidBeginEditingNotification, object: nil, queue: nil
    ) { notification in
        guard let field = notification.object as? UITextField else { return }
        let isRideSearch = field.accessibilityIdentifier == "Ride search"
            || field.placeholder == "Search rides or lands"
        let uptimeMs = Int(ProcessInfo.processInfo.systemUptime * 1_000)
        RideSearchColdControlScreen.timingLog.notice(
            "event=control-native-begin-editing isRideSearch=\(isRideSearch, privacy: .public) uptimeMs=\(uptimeMs, privacy: .public)"
        )
    }

    private func logTiming(_ event: String) {
        if event == "search-mounted" { _ = Self.nativeEditingObserver }
        let uptimeMs = Int(ProcessInfo.processInfo.systemUptime * 1_000)
        Self.timingLog.notice("event=control-\(event, privacy: .public) uptimeMs=\(uptimeMs, privacy: .public)")
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current rides").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                    HStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").foregroundStyle(Color.pivotMuted)
                            TextField("Search rides or lands", text: $query)
                                .font(.body)
                                .accessibilityIdentifier("Ride search")
                                .focused($searchFocused)
                                .submitLabel(.search)
                                .onSubmit { searchFocused = false }
                                .onAppear { logTiming("search-mounted") }
                                .onChange(of: searchFocused) { _, focused in
                                    if focused { logTiming("focus-acquired") }
                                }
                                .onChange(of: query) { oldQuery, newQuery in
                                    if oldQuery.isEmpty && !newQuery.isEmpty {
                                        logTiming("first-query-nonempty")
                                    }
                                }
                                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                                    logTiming("keyboard-will-show")
                                }
                                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                                    logTiming("keyboard-did-show")
                                }
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            if !query.isEmpty {
                                Button { query = "" } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.pivotMuted)
                                }
                                .frame(minWidth: 32, minHeight: 44)
                                .accessibilityLabel("Clear ride search")
                            }
                        }
                        .padding(.horizontal, 13)
                        .frame(minHeight: 46)
                        .background(Color.pivotBackground.opacity(0.7), in: Capsule())
                        .overlay { Capsule().strokeBorder(Color.pivotBorder, lineWidth: 1).allowsHitTesting(false) }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("ride-search-control")
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 46, height: 46)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("waits-controls-row")
                .listRowInsets(EdgeInsets())
            }
            .listRowBackground(Color.pivotSurface)
        }
        .listStyle(.insetGrouped)
        .contentMargins(.horizontal, 14, for: .scrollContent)
        .contentMargins(.top, 8, for: .scrollContent)
        .listSectionSpacing(8)
        .scrollContentBackground(.hidden)
        .background(Color.pivotBackground)
        .scrollDismissesKeyboard(.interactively)
    }
}
#endif

#if canImport(UIKit)
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
#endif

struct PivotUITestTypeSize: ViewModifier {
    var probeIdentifier: String? = nil

    @ViewBuilder func body(content: Content) -> some View {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-large-type") ||
           ProcessInfo.processInfo.arguments.contains("--ui-largest-type") {
            content
                .overlay(alignment: .topLeading) {
                    if let probeIdentifier {
                        // Measure a real body-font line in the presented hierarchy.
                        // The corner probe never handles touches or covers map pins.
                        Text("A").font(.body).fixedSize().opacity(0.02)
                            .accessibilityIdentifier(probeIdentifier)
                            .allowsHitTesting(false)
                    }
                }
                .dynamicTypeSize(ProcessInfo.processInfo.arguments.contains("--ui-largest-type") ? .accessibility5 : .accessibility2)
        } else { content }
#else
        content
#endif
    }
}
