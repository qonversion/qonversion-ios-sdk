//
//  AppDelegate.swift
//  SwiftEx
//
//  Created by Bogdan Novikov on 21/05/2019.
//  Copyright © 2019 axcic. All rights reserved.
//

import UIKit
import Qonversion

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        Qonversion.launch(withKey: "projectKey", autoTrackPurchases: true) { (uid) in
            // need to pass uid to FBSDKCoreKit.AppEvents.userID
        }
        
        return true
    }
}

