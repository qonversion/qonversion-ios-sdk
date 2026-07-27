//
//  AppDelegate.swift
//  Sample
//
//  Created by Suren Sarkisyan on 28.02.2024.
//

import UIKit
import Qonversion
import NoCodes

enum SampleConfig {
    // Replace with your project key from the Qonversion Dashboard.
    static let projectKey = "YOUR_PROJECT_KEY"
}

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let configuration = Qonversion.Configuration(apiKey: SampleConfig.projectKey, launchMode: .subscriptionManagement)
        Qonversion.initialize(with: configuration)

        // No-Codes is initialized separately, after the main SDK. The bundled
        // Sample/nocodes_fallbacks.json backs the screens when the API is
        // unreachable.
        let noCodesConfiguration = NoCodesConfiguration(projectKey: SampleConfig.projectKey)
        NoCodes.initialize(with: noCodesConfiguration)

        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
    }
}
