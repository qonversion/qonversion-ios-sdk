//
//  OfferingsViewController.swift
//  Sample
//
//  Created by Surik Sarkisyan on 28.05.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

import Foundation
import UIKit
import Qonversion

class OfferingsViewController: UIViewController {
  
  var offerings: Qonversion.Offerings!
  
  @IBOutlet weak var tableView: UITableView!
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    title = "Offerings"
  }
  
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    
    navigationController?.isNavigationBarHidden = false
  }
  
  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    
    navigationController?.isNavigationBarHidden = true
  }
  
  func showAlert(with title: String, message: String) {
    let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
    let action = UIAlertAction(title: "OK", style: .cancel, handler: nil)
    
    alertController.addAction(action)
    
    navigationController?.present(alertController, animated: true, completion: nil)
  }
  
}

extension OfferingsViewController: UITableViewDataSource {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return offerings.main?.products.count ?? 0
  }
  
  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let product: Qonversion.Product = (offerings.main?.products[indexPath.row])!
    
    let cell = tableView.dequeueReusableCell(withIdentifier: "OfferingsTableViewCell", for: indexPath) as! OfferingsTableViewCell
    cell.setup(with: product)
    
    return cell
  }
  
}

extension OfferingsViewController: UITableViewDelegate {
  
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    
    guard let product: Qonversion.Product = offerings.main?.products[indexPath.row] else { return }
    
    Qonversion.shared().purchaseProduct(product) { [weak self] result, error, canceled in
      guard !canceled else { return }
      
      guard error == nil else {
        self?.showAlert(with: "Error", message: error?.localizedDescription ?? "Purchase error")
        return
      }
      
      self?.showAlert(with: "WOW", message: "Purchase succeeded")
    }
  }
  
}

