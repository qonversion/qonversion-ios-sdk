//
//  AppDelegate.swift
//  Sample
//
//  Created by Sam Mejlumyan on 13.08.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

import UIKit
import Qonversion

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

  var window: UIWindow?
  
  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    Qonversion.launch(withKey: "PV77YHL7qnGvsdmpTs7gimsxUvY-Znl2")
    Qonversion.setPromoPurchasesDelegate(self)
    
    return true
  }
  
}

extension AppDelegate: QNPromoPurchasesDelegate {
  
  func shouldPurchasePromoProduct(withIdentifier productID: String, executionBlock: @escaping Qonversion.PromoPurchaseCompletionHandler) {
    // check productID value in case if you want to enable promoted purchase only for specific products
    
    let compeltion: Qonversion.PurchaseCompletionHandler = {result, error, flag in
      // handle purchased product or error
    }
    
    executionBlock(compeltion)
  }
  
}
