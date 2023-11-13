//
//  ViewController.swift
//  Sample
//
//  Created by Sam Mejlumyan on 13.08.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
  
  @IBOutlet weak var mainProductSubscriptionButton: UIButton!
  @IBOutlet weak var inAppPurchaseButton: UIButton!
  @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
  @IBOutlet weak var subscriptionTitleLabel: UILabel!
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    navigationController?.isNavigationBarHidden = true
    
    subscriptionTitleLabel.text = ""
    mainProductSubscriptionButton.layer.cornerRadius = 20.0
    inAppPurchaseButton.layer.cornerRadius = 20.0
    inAppPurchaseButton.layer.borderWidth = 1.0
  }
  
  func showAlert(with title: String, message: String) {
    let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
    let action = UIAlertAction(title: "OK", style: .cancel, handler: nil)
    
    alertController.addAction(action)
    
    navigationController?.present(alertController, animated: true, completion: nil)
  }

  @IBAction func didTapMainProductSubscriptionButton(_ sender: Any) {
    // purchase subscription here
  }
  
  @IBAction func didTapInAppPurchaseButton(_ sender: Any) {
    // purchase consumable/nonconsumable in-app here
  }
  
  @IBAction func didTapRestorePurchasesButton(_ sender: Any) {
    // restore purchases
  }
  
}
