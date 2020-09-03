//
//  ViewController.swift
//  Sample App
//
//  Created by Surik Sarkisyan on 01.09.2020.
//  Copyright © 2020 qonverison. All rights reserved.
//

import UIKit
import SwiftyStoreKit

class ViewController: UIViewController {
    
    @IBOutlet var buySubscriptionButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        buySubscriptionButton.layer.cornerRadius = buySubscriptionButton.bounds.height / 8.0
    }
    
    @IBAction func didTapBuySubscriptionButton(_ sender: Any) {
        SwiftyStoreKit.purchaseProduct("your_product_id", quantity: 1, atomically: false) { result in
            switch result {
            case .success(let product):
                print("Purchase Success: \(product.product)")
                if product.needsFinishTransaction {
                    SwiftyStoreKit.finishTransaction(product.transaction)
                }
            case .error(let error):
                switch error.code {
                case .unknown:
                    print("Unknown error. Please contact support")
                case .clientInvalid:
                    print("Not allowed to make the payment")
                case .paymentCancelled: break
                case .paymentInvalid:
                    print("The purchase identifier was invalid")
                case .paymentNotAllowed:
                    print("The device is not allowed to make the payment")
                case .storeProductNotAvailable:
                    print("The product is not available in the current storefront")
                case .cloudServicePermissionDenied:
                    print("Access to cloud service information is not allowed")
                case .cloudServiceNetworkConnectionFailed:
                    print("Could not connect to the network")
                case .cloudServiceRevoked:
                    print("User has revoked permission to use this cloud service")
                default:
                    print((error as NSError).localizedDescription)
                }
            }
        }
    }

}
