//
//  AppDelegate.swift
//  Sample
//
//  Created by Sam Mejlumyan on 13.08.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

import UIKit
import Qonversion
import AppsFlyerLib

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

  var window: UIWindow?
  
  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    Qonversion.launch(withKey: "PV77YHL7qnGvsdmpTs7gimsxUvY-Znl2")
    
    Qonversion.setProperty(.appsFlyerUserID, value: AppsFlyerLib.shared().getAppsFlyerUID())
    AppsFlyerLib.shared().appsFlyerDevKey = "appsFlyerDevKey"
    AppsFlyerLib.shared().appleAppID = "appleAppID"
    AppsFlyerLib.shared().delegate = self
    AppsFlyerLib.shared().getAppsFlyerUID()
    
    registerForNotifications()
    
    return true
  }
  
  func registerForNotifications() {
      UNUserNotificationCenter.current().delegate = self
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { (_, _) in }
      UIApplication.shared.registerForRemoteNotifications()
  }
  
}

extension AppDelegate: UNUserNotificationCenterDelegate {
  
  func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
      print("error: \(error)")
  }

  func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    Qonversion.setProperty(.pushToken, value: tokenString)
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
      
    completionHandler()
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
      
    completionHandler([])
  }
  
}

extension AppDelegate: AppsFlyerLibDelegate {
  
  func onConversionDataSuccess(_ conversionInfo: [AnyHashable : Any]) {
    Qonversion.addAttributionData(conversionInfo, from: .appsFlyer)
  }
  
  func onConversionDataFail(_ error: Error) {
    
  }
  
}
