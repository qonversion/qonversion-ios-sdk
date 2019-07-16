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
        
        Qonversion.launch(withKey: "FS0uWnuNG4jbU2tBW54JFsSznt8KIfbf", autoTrackPurchases: true) { (uid) in
            print(uid)
        }
        
        return true
    }
}

