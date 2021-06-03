//
//  OfferingsTableViewCell.swift
//  Sample
//
//  Created by Surik Sarkisyan on 28.05.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

import Foundation
import UIKit
import Qonversion

class OfferingsTableViewCell: UITableViewCell {
  
  @IBOutlet weak var priceLabel: UILabel!
  @IBOutlet weak var titleLabel: UILabel!
  @IBOutlet weak var descriptionLabel: UILabel!
  
  func setup(with product: Qonversion.Product) {
    let duration: String = product.type == .oneTime ? "forever" : product.prettyDuration
    priceLabel.text = "\(product.prettyPrice) / \(duration)"
    titleLabel.text = product.skProduct?.localizedTitle
    descriptionLabel.text = product.skProduct?.localizedDescription
  }
  
}
