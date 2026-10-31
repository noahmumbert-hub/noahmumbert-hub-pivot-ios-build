import SwiftUI
#if canImport(UIKit)
import UIKit
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
        } else {
            RootView()
        }
#else
        RootView()
#endif
    }
}

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
