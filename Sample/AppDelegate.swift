//
//  AppDelegate.swift
//  Sample
//
//  Created by Sam Mejlumyan on 13.08.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

import UIKit
import Qonversion
import Firebase

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

  var window: UIWindow?
  
  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    FirebaseApp.configure()
    
    let config = Qonversion.Configuration(projectKey: "PV77YHL7qnGvsdmpTs7gimsxUvY-Znl2", launchMode: .subscriptionManagement)
    config.setEnvironment(.sandbox)
    config.setEntitlementsCacheLifetime(.year)
    Qonversion.initWithConfig(config)
    Qonversion.shared().setPromoPurchasesDelegate(self)
    Qonversion.shared().collectAdvertisingId()
    registerForNotifications()
    QonversionSwift.shared.syncStoreKit2Purchases()
    
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
    Qonversion.Automations.shared().setNotificationsToken(deviceToken)
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
    let isPushHandled: Bool = Qonversion.Automations.shared().handleNotification(response.notification.request.content.userInfo)
    if !isPushHandled {
      // Qonversion can not handle this push.
    }
    completionHandler()
  }
  
  func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    completionHandler([.alert, .badge, .sound])
  }
  
}

extension AppDelegate: Qonversion.PromoPurchasesDelegate {
  
  func shouldPurchasePromoProduct(withIdentifier productID: String, executionBlock: @escaping Qonversion.PromoPurchaseCompletionHandler) {
    // check productID value in case if you want to enable promoted purchase only for specific products
    
    let compeltion: Qonversion.PurchaseCompletionHandler = {result, error, flag in
      // handle purchased product or error
    }
    
    executionBlock(compeltion)
  }
  
}
