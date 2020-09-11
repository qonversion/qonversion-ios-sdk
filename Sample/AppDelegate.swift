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
    
    AppsFlyerTracker.shared().appsFlyerDevKey = "appsFlyerDevKey"
    AppsFlyerTracker.shared().appleAppID = "appleAppID"
    AppsFlyerTracker.shared().delegate = self
    
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
