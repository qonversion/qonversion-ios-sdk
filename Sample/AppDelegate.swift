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
//  
  var window: UIWindow?
  
  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    Qonversion.launch(withKey: "your_launch_key")
    
    AppsFlyerTracker.shared().appsFlyerDevKey = "appsFlyerDevKey"
    AppsFlyerTracker.shared().appleAppID = "appleAppID"
    AppsFlyerTracker.shared().delegate = self
    
    Qonversion.checkPermissions { (permissions, error) in
      if let _ = error {
        // handle error
        return
      }
      
      if let permission = permissions["your_permission_name"], permission.isActive {
        switch permission.renewState {
        case .willRenew, .nonRenewable:
          // .willRenew is state for auto-renewable purchases
          // .nonRenewable is state for in-app purchases that unlock the permission lifetime
          break
        case .billingIssue:
          // Grace period: permission is active, but there was some billing issue.
          // Prompt the user to update the payment method.
          break
        case .cancelled:
          // The user canceled the subscription, but the subscription has not expired yet.
          // Prompt the user to resubscribe with some special offer.
          break
        default: break
        }
      }
    }
    
    return true
  }
  
}


extension AppDelegate: AppsFlyerTrackerDelegate {
  
  func onConversionDataSuccess(_ conversionInfo: [AnyHashable : Any]) {
    Qonversion.addAttributionData(conversionInfo, from: .appsFlyer)
  }
  
  func onConversionDataFail(_ error: Error) {
    
  }
  
}
