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

    var body: some Scene {
        WindowGroup {
            appContent
                .environmentObject(store)
                .environment(\.pivotAccent, PivotAccent.resolve(selectedAccent).color)
                .tint(PivotAccent.resolve(selectedAccent).color)
                .preferredColorScheme(.dark)
                .onChange(of: selectedAccent) { _, _ in
                    store.synchronizeLiveActivity()
                }
        }
    }

    @ViewBuilder
    private var appContent: some View {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--wait-forecast-ui-test") {
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
