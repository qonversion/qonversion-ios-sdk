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

class ViewController: UIViewController, NoCodesDelegate, NoCodesScreenCustomizationDelegate {
  func noCodesFailedToExecute(action: NoCodesAction, error: (any Error)?) {
    if let error {
      print(error)
    }
  }
  
  func noCodesFinishedExecuting(action: NoCodesAction) {
    print(action)
  }
  
  func noCodesFailedToLoadScreen(error: Error?) {
    if let error {
      print("NoCodes failed to load screen: \(error)")
    }
    NoCodes.shared.close()
  }
  
  let projectKey = "PV77YHL7qnGvsdmpTs7gimsxUvY-Znl2"
  let firstPurchaseButtonProduct = "weekly"
  let secondPurchaseButtonProduct = "in_app"
  
  private var lastEnteredContextKey: String? {
    get {
      UserDefaults.standard.string(forKey: "lastEnteredContextKey")
    }
    set {
      UserDefaults.standard.set(newValue, forKey: "lastEnteredContextKey")
    }
  }
  
  private var customProjectKey: String? {
    get {
      UserDefaults.standard.string(forKey: "customProjectKey")
    }
    set {
      UserDefaults.standard.set(newValue, forKey: "customProjectKey")
    }
  }
  
  private var customProxyURL: String? {
    get {
      UserDefaults.standard.string(forKey: "customProxyURL")
    }
    set {
      UserDefaults.standard.set(newValue, forKey: "customProxyURL")
    }
  }
  
  @IBOutlet weak var mainProductSubscriptionButton: UIButton!
  @IBOutlet weak var inAppPurchaseButton: UIButton!
  @IBOutlet weak var offeringsButton: UIButton!
  @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
  @IBOutlet weak var subscriptionTitleLabel: UILabel!
  @IBOutlet weak var checkActivePermissionsButton: UIButton!
  @IBOutlet weak var logoutButton: UIButton!
  @IBOutlet weak var logoImageView: UIImageView!
  
  var permissions: [String: Qonversion.Entitlement] = [:]
  var products: [String: Qonversion.Product] = [:]
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    // Setup logo tap gesture
    setupLogoTapGesture()
    
    // Setup NoCodes delegates
    NoCodes.shared.set(screenCustomizationDelegate: self)
    NoCodes.shared.set(delegate: self)
    
    navigationController?.isNavigationBarHidden = true
    
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
  
  private func setupLogoTapGesture() {
    let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleLogoTap))
    tapGesture.numberOfTapsRequired = 5
    logoImageView.isUserInteractionEnabled = true
    logoImageView.addGestureRecognizer(tapGesture)
  }
  
  @objc private func handleLogoTap() {
    showConfigurationPopup()
  }
  
  private func showConfigurationPopup() {
    let alertController = UIAlertController(title: "Configuration", message: "Enter custom settings", preferredStyle: .alert)
    
    // Project Key field
    alertController.addTextField { [weak self] textField in
      textField.placeholder = "Project Key"
      textField.text = self?.customProjectKey ?? self?.projectKey
      textField.clearButtonMode = .always
    }
    
    // Proxy URL field
    alertController.addTextField { [weak self] textField in
      textField.placeholder = "Proxy URL (optional)"
      textField.text = self?.customProxyURL
      textField.clearButtonMode = .always
    }
    
    let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
    let saveAction = UIAlertAction(title: "Save", style: .default) { [weak self] _ in
      guard let self = self else { return }
      
      let projectKeyField = alertController.textFields?[0]
      let proxyURLField = alertController.textFields?[1]
      
      let newProjectKey = projectKeyField?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
      let newProxyURL = proxyURLField?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
      
      // Validate project key
      guard let projectKey = newProjectKey, !projectKey.isEmpty else {
        self.showAlert(with: "Error", message: "Project Key cannot be empty")
        return
      }
      
      // Save settings
      self.customProjectKey = projectKey
      
      // Only update proxyURL if it's not empty, otherwise keep current value
      if let proxyURL = newProxyURL, !proxyURL.isEmpty {
        self.customProxyURL = proxyURL
      }
      // If proxyURL is empty, we don't change self.customProxyURL (keep current value)
      
      self.showAlert(with: "Success", message: "Configuration saved. Please restart the app to apply changes.")
    }
    
    alertController.addAction(cancelAction)
    alertController.addAction(saveAction)
    
    present(alertController, animated: true)
  }
  
  func checkProducts() {
    activityIndicator.startAnimating()
    
    Qonversion.shared().products { [weak self] (result, error) in
      guard let self = self else { return }
      
      self.activityIndicator.stopAnimating()
      
      self.products = result
      
      if let mainSubscription = result[firstPurchaseButtonProduct] {
        let permission: Qonversion.Entitlement? = self.permissions["plus"]
        let isActive = permission?.isActive ?? false
        let title: String = isActive ? "Successfully purchased" : "Subscribe for \(mainSubscription.prettyPrice) / \(mainSubscription.prettyDuration)"
        self.mainProductSubscriptionButton.setTitle(title, for: .normal)
        self.mainProductSubscriptionButton.backgroundColor = isActive ? .systemGreen : self.mainProductSubscriptionButton.backgroundColor
        self.checkActivePermissionsButton.isHidden = isActive ? true : false
      }
      
      if let inAppPurchase = result[secondPurchaseButtonProduct] {
        let permission: Qonversion.Entitlement? = self.permissions["standart"]
        let isActive = permission?.isActive ?? false
        let title: String = isActive ? "Successfully purchased" : "Buy for \(inAppPurchase.prettyPrice)"
        self.inAppPurchaseButton.setTitle(title, for: .normal)
        self.inAppPurchaseButton.backgroundColor = isActive ? .systemGreen : self.inAppPurchaseButton.backgroundColor
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
    if let product = self.products[firstPurchaseButtonProduct] {
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
    if let product = self.products[secondPurchaseButtonProduct] {
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
  
  @IBAction func didTapShowPaywallButton(_ sender: Any) {
    let alertController = UIAlertController(title: "Enter context key", message: nil, preferredStyle: .alert)
    
    alertController.addTextField { [weak self] textField in
      textField.placeholder = "Context key"
      textField.text = self?.lastEnteredContextKey
      textField.clearButtonMode = .always
    }
    
    let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
    let showAction = UIAlertAction(title: "Show No-Code Screen", style: .default) { [weak self] _ in
      guard let contextKey = alertController.textFields?.first?.text, !contextKey.isEmpty else { return }
      self?.lastEnteredContextKey = contextKey
      NoCodes.shared.showScreen(withContextKey: contextKey)
    }
    
    alertController.addAction(cancelAction)
    alertController.addAction(showAction)
    
    present(alertController, animated: true)
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
