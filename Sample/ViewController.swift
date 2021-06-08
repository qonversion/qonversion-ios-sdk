//
//  ViewController.swift
//  Sample
//
//  Created by Sam Mejlumyan on 13.08.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

import UIKit
import Qonversion

class ViewController: UIViewController {
  
  @IBOutlet weak var mainProductSubscriptionButton: UIButton!
  @IBOutlet weak var inAppPurchseButton: UIButton!
  @IBOutlet weak var offeringsButton: UIButton!
  @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
  @IBOutlet weak var subscriptionTitleLabel: UILabel!
  @IBOutlet weak var checkActivePermissionsButton: UIButton!
  
  var permissions: [String: Qonversion.Permission] = [:]
  var products: [String: Qonversion.Product] = [:]
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    navigationController?.isNavigationBarHidden = true
    
    Qonversion.Automations.setDelegate(self)
    
    subscriptionTitleLabel.text = ""
    mainProductSubscriptionButton.layer.cornerRadius = 20.0
    inAppPurchseButton.layer.cornerRadius = 20.0
    inAppPurchseButton.layer.borderWidth = 1.0
    inAppPurchseButton.layer.borderColor = mainProductSubscriptionButton.backgroundColor?.cgColor
    
    offeringsButton.layer.cornerRadius = 20.0
    
    Qonversion.checkPermissions { [weak self] (permissions, error) in
      guard let self = self else { return }

      self.activityIndicator.stopAnimating()

      self.checkProducts()
      
      if let _ = error {
        // handle error
        return
      }
      
      guard permissions.values.contains(where: {$0.isActive == true}) else { return }
      
      self.checkActivePermissionsButton.isHidden = false
      
      self.permissions = permissions
      
      self.showActivePermissionsScreen()
    }
  }
  
  func checkProducts() {
    activityIndicator.startAnimating()
    
    Qonversion.products { [weak self] (result, error) in
      guard let self = self else { return }
      
      self.activityIndicator.stopAnimating()
      
      self.products = result
      
      if let inAppPurchase = result["consumable"] {
        let permission: Qonversion.Permission? = self.permissions["standart"]
        let isActive = permission?.isActive ?? false
        let title: String = isActive ? "Purchased" : "Buy for \(inAppPurchase.prettyPrice)"
        self.inAppPurchseButton.setTitle(title, for: .normal)
      }
      
      if let mainSubscription = result["main"] {
        let permission: Qonversion.Permission? = self.permissions["plus"]
        let isActive = permission?.isActive ?? false
        let title: String = isActive ? "Purchased" : "Subscribe for \(mainSubscription.prettyPrice) / \(mainSubscription.prettyDuration)"
        self.mainProductSubscriptionButton.setTitle(title, for: .normal)
      }
    }
  }
  
  func showAlert(with title: String, message: String) {
    let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
    let action = UIAlertAction(title: "OK", style: .cancel, handler: nil)
    
    alertController.addAction(action)
    
    navigationController?.present(alertController, animated: true, completion: nil)
  }
  
  func showActivePermissionsScreen() {
    let activePermissionsViewController = self.storyboard?.instantiateViewController(withIdentifier: "ActivePermissionsViewController") as! ActivePermissionsViewController
    activePermissionsViewController.permissions = permissions.map { $0.value }
    
    self.navigationController?.pushViewController(activePermissionsViewController, animated: true)
  }
  
  @IBAction func didTapMainProductSubscriptionButton(_ sender: Any) {
    if let product = self.products["main"] {
      activityIndicator.startAnimating()
      Qonversion.purchase(product.qonversionID) { [weak self] (result, error, flag) in
        guard let self = self else { return }
        
        self.activityIndicator.stopAnimating()
        
        if let error = error {
          return self.showAlert(with: "Error", message: error.localizedDescription)
        }
        
        if !result.isEmpty {
          self.mainProductSubscriptionButton.setTitle("Purchased", for: .normal)
        }
        
      }
    }
  }
  
  @IBAction func didTapInAppPurchaseButton(_ sender: Any) {
    if let product = self.products["consumable"] {
      activityIndicator.startAnimating()
      Qonversion.purchaseProduct(product) { [weak self] (result, error, flag) in
        guard let self = self else { return }
        
        self.activityIndicator.stopAnimating()
        
        if let error = error {
          return self.showAlert(with: "Error", message: error.localizedDescription)
        }
        
        if !result.isEmpty {
          self.inAppPurchseButton.setTitle("Purchased", for: .normal)
        }
      }
    }
  }
  
  @IBAction func didTapOfferingsButton(_ sender: Any) {
    offeringsButton.isEnabled = false
    Qonversion.offerings { [weak self] offerings, error in
      self?.offeringsButton.isEnabled = true
      guard let offerings: Qonversion.Offerings = offerings else { return }
      
      let offeringsViewController = self?.storyboard?.instantiateViewController(withIdentifier: "OfferingsViewController") as! OfferingsViewController
      offeringsViewController.offerings = offerings
      
      self?.navigationController?.pushViewController(offeringsViewController, animated: true)
    }
  }
  
  @IBAction func didTapRestorePurchasesButton(_ sender: Any) {
    activityIndicator.startAnimating()
    Qonversion.restore { [weak self] (permissions, error) in
      guard let self = self else { return }
      
      self.activityIndicator.stopAnimating()
      
      if let error = error {
        return self.showAlert(with: "Error", message: error.localizedDescription)
      }
      
      guard permissions.values.contains(where: {$0.isActive == true}) else {
        return self.showAlert(with: "Error", message: "No purchases to restore")
      }
      
      self.checkActivePermissionsButton.isHidden = false
      
      self.permissions = permissions
      
      if let permission: Qonversion.Permission = self.permissions["standart"], permission.isActive {
        self.inAppPurchseButton.setTitle("Restored", for: .normal)
      }
      
      if let permission: Qonversion.Permission = self.permissions["plus"], permission.isActive {
        self.mainProductSubscriptionButton.setTitle("Restored", for: .normal)
      }
    }
  }
  
  @IBAction func didTapCheckActivePermissionsButton(_ sender: Any) {
    self.showActivePermissionsScreen()
  }
  
}

extension Qonversion.Product {
  var prettyDuration: String {
    switch duration {
    case .durationWeekly:
      return "weekly"
    case .duration3Months:
      return "3 months"
    case .duration6Months:
      return  "6 months"
    case .durationAnnual:
      return "Annual"
    case .durationLifetime:
      return "Lifetime"
    case .durationMonthly:
      return "Monthly"
    case .durationUnknown:
      return "Unknown"
    @unknown default:
      return ""
    }
  }
}

extension ViewController: Qonversion.AutomationsDelegate {
  func controllerForNavigation() -> UIViewController {
    return self
  }
}
