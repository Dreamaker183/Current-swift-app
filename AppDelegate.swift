import UIKit
import SwiftUI
import UserNotifications // Required for notification handling

@main
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Create the SwiftUI ContentView.
        let contentView = ContentView()

        // Create a new window covering the entire screen.
        let window = UIWindow(frame: UIScreen.main.bounds)

        // Set the rootViewController to a UIHostingController hosting your SwiftUI ContentView.
        window.rootViewController = UIHostingController(rootView: contentView)

        // Make this window the key window and show it.
        self.window = window
        window.makeKeyAndVisible()

        // Set the AppDelegate as the notification center delegate
        UNUserNotificationCenter.current().delegate = self

        // Request notification authorization early in the app lifecycle
        NotificationManager.shared.requestAuthorization()

        return true
    }

    // Handle notifications when the app is in the foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Display the notification as a banner with sound when the app is active
        completionHandler([.banner, .sound])
    }
}
