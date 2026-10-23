import SwiftUI
import UIKit

@main
struct CoastFuelApp: App {
    @UIApplicationDelegateAdaptor(CoastFuelAppDelegate.self) private var appDelegate
    var body: some Scene {
        WindowGroup {
            ContentView()
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    TankPromotionCard()
                }
                .preferredColorScheme(.dark)
        }
    }
}

final class CoastFuelAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: session.role == .windowApplication ? "Phone" : "CarPlay", sessionRole: session.role)
        if session.role == .windowApplication { configuration.delegateClass = nil }
        else { configuration.delegateClass = CarPlaySceneDelegate.self }
        return configuration
    }
}
