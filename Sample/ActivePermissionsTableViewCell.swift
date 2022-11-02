//
//  ActivePermissionsTableViewCell.swift
//  Sample
//
//  Created by Surik Sarkisyan on 07.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

import UIKit
import Qonversion

class ActivePermissionsTableViewCell: UITableViewCell {
  
  @IBOutlet weak var permissionIdLabel: UILabel!
  @IBOutlet weak var productIdLabel: UILabel!
  @IBOutlet weak var renewStateLabel: UILabel!
  
  func setup(with permission: Qonversion.Entitlement) {
    permissionIdLabel.text = "Permission id: \(permission.entitlementID)"
    productIdLabel.text = "Product id: \(permission.productID)"
    var renewState = ""
    switch permission.renewState {
    case .nonRenewable:
      renewState = "non renewable"
    case .unknown:
      renewState = "unknown"
    case .willRenew:
      renewState = "will renew"
    case .cancelled:
      renewState = "canceled"
    case .billingIssue:
      renewState = "billing issue"
    default:
      renewState = "\(permission.renewState.rawValue)"
    }
    
    renewStateLabel.text = "Renew state: \(renewState)"
  }
  
}
