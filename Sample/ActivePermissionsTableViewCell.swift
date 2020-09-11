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
  
  func setup(with permission: Qonversion.Permission) {
    permissionIdLabel.text = "Permission id: \(permission.permissionID)"
    productIdLabel.text = "Product id: \(permission.productID)"
    var renewState = ""
    switch permission.renewState {
    case Qonversion.PermissionRenewState.nonRenewable:
      renewState = "non renewable"
    case Qonversion.PermissionRenewState.unknown:
      renewState = "unknown"
    case Qonversion.PermissionRenewState.willRenew:
      renewState = "will renew"
    case Qonversion.PermissionRenewState.cancelled:
      renewState = "canceled"
    case Qonversion.PermissionRenewState.billingIssue:
      renewState = "billing issue"
    default:
      renewState = "\(permission.renewState.rawValue)"
    }
    
    renewStateLabel.text = "Renew state: \(renewState)"
  }
  
}
