//
//  ViewController.swift
//  Sample
//
//  Created by Sam Mejlumyan on 13.08.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

import UIKit
import Qonversion
import GoogleSignIn
import FirebaseAuth

class ViewController: UIViewController {
  
  @IBOutlet weak var mainProductSubscriptionButton: UIButton!
  @IBOutlet weak var inAppPurchaseButton: UIButton!
  @IBOutlet weak var offeringsButton: UIButton!
  @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
  @IBOutlet weak var subscriptionTitleLabel: UILabel!
  @IBOutlet weak var checkActivePermissionsButton: UIButton!
  @IBOutlet weak var logoutButton: UIButton!
  
  var permissions: [String: Qonversion.Entitlement] = [:]
  var products: [String: Qonversion.Product] = [:]
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    navigationController?.isNavigationBarHidden = true
    
    Qonversion.Automations.shared().setDelegate(self)
    Qonversion.Automations.shared().setScreenCustomizationDelegate(self)
    
    subscriptionTitleLabel.text = ""
    mainProductSubscriptionButton.layer.cornerRadius = 20.0
    inAppPurchaseButton.layer.cornerRadius = 20.0
    inAppPurchaseButton.layer.borderWidth = 1.0
    
    logoutButton.layer.cornerRadius = logoutButton.frame.height / 2.0
    logoutButton.layer.borderWidth = 1.0
    logoutButton.layer.borderColor = logoutButton.backgroundColor?.cgColor
    logoutButton.layer.borderColor = mainProductSubscriptionButton.backgroundColor?.cgColor
    
    offeringsButton.layer.cornerRadius = 20.0
    
    Qonversion.shared().checkEntitlements { [weak self] (permissions, error) in
      guard let self = self else { return }

      self.permissions = permissions
      
      self.checkProducts()
      
      self.activityIndicator.stopAnimating()
      
      if let _ = error {
        // handle error
        return
      }
      
      guard permissions.values.contains(where: {$0.isActive == true}) else { return }
      
      self.checkActivePermissionsButton.isHidden = false
      
      self.showActivePermissionsScreen()
    }
    
    Qonversion.shared().offerings { offerings, error in
      
    }
  }
  
  func checkProducts() {
    activityIndicator.startAnimating()
    
    Qonversion.shared().products { [weak self] (result, error) in
      guard let self = self else { return }
      
      self.activityIndicator.stopAnimating()
      
      self.products = result
      
      if let inAppPurchase = result["consumable"] {
        let permission: Qonversion.Entitlement? = self.permissions["standart"]
        let isActive = permission?.isActive ?? false
        let title: String = isActive ? "Successfully purchased" : "Buy for \(inAppPurchase.prettyPrice)"
        self.inAppPurchaseButton.setTitle(title, for: .normal)
        self.inAppPurchaseButton.backgroundColor = isActive ? .systemGreen : self.inAppPurchaseButton.backgroundColor
        self.checkActivePermissionsButton.isHidden = isActive ? true : false
      }
      
      if let mainSubscription = result["subs_plus_trial"] {
        let permission: Qonversion.Entitlement? = self.permissions["plus"]
        let isActive = permission?.isActive ?? false
        let title: String = isActive ? "Successfully purchased" : "Subscribe for \(mainSubscription.prettyPrice) / \(mainSubscription.prettyDuration)"
        self.mainProductSubscriptionButton.setTitle(title, for: .normal)
        self.mainProductSubscriptionButton.backgroundColor = isActive ? .systemGreen : self.mainProductSubscriptionButton.backgroundColor
        self.checkActivePermissionsButton.isHidden = isActive ? true : false
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
    if let product = self.products["subs_plus_trial"] {
      activityIndicator.startAnimating()
      Qonversion.shared().purchase(product.qonversionID) { [weak self] (result, error, flag) in
        guard let self = self else { return }
        
        self.activityIndicator.stopAnimating()
        
        if let error = error {
          return self.showAlert(with: "Error", message: error.localizedDescription)
        }
        
        if !result.isEmpty {
          self.mainProductSubscriptionButton.setTitle("Successfully purchased", for: .normal)
          self.mainProductSubscriptionButton.backgroundColor = .systemGreen
        }
        
      }
    }
  }
  
  @IBAction func didTapInAppPurchaseButton(_ sender: Any) {
    if let product = self.products["consumable"] {
      activityIndicator.startAnimating()
      Qonversion.shared().purchaseProduct(product) { [weak self] (result, error, flag) in
        guard let self = self else { return }
        
        self.activityIndicator.stopAnimating()
        
        if let error = error {
          return self.showAlert(with: "Error", message: error.localizedDescription)
        }
        
        if !result.isEmpty {
          self.inAppPurchaseButton.setTitle("Successfully purchased", for: .normal)
          self.inAppPurchaseButton.backgroundColor = .systemGreen
        }
      }
    }
  }
  
  @IBAction func didTapOfferingsButton(_ sender: Any) {
    offeringsButton.isEnabled = false
    Qonversion.shared().offerings { [weak self] offerings, error in
      self?.offeringsButton.isEnabled = true
      guard let offerings: Qonversion.Offerings = offerings else { return }
      
      let offeringsViewController = self?.storyboard?.instantiateViewController(withIdentifier: "OfferingsViewController") as! OfferingsViewController
      offeringsViewController.offerings = offerings
      
      self?.navigationController?.pushViewController(offeringsViewController, animated: true)
    }
  }
  
  @IBAction func didTapRestorePurchasesButton(_ sender: Any) {
    activityIndicator.startAnimating()
    Qonversion.shared().restore { [weak self] (permissions, error) in
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
      
      if let permission: Qonversion.Entitlement = self.permissions["standart"], permission.isActive {
        self.inAppPurchaseButton.setTitle("Restored", for: .normal)
      }
      
      if let permission: Qonversion.Entitlement = self.permissions["plus"], permission.isActive {
        self.mainProductSubscriptionButton.setTitle("Restored", for: .normal)
      }
    }
  }
  
  @IBAction func didTapCheckActivePermissionsButton(_ sender: Any) {
    self.showActivePermissionsScreen()
  }
  
  @IBAction func didTapLogoutButton(_ sender: Any) {
    
    do {
      try Auth.auth().signOut()
      GIDSignIn.sharedInstance.signOut()
      Qonversion.shared().logout()
      self.navigationController?.popViewController(animated: true)
    } catch {
      // handle error
    }
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

extension ViewController: Qonversion.ScreenCustomizationDelegate {
  func presentationConfigurationForScreen(_ screenId: String) -> Qonversion.ScreenPresentationConfiguration {
    return Qonversion.ScreenPresentationConfiguration(presentationStyle: .push, animated: true)
  }
}
