//
//  Action.swift
//  QonversionNoCodes
//
//  Created by Suren Sarkisyan on 24.12.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation

public extension NoCodes {
  
  enum ActionType {
    case unknown
    case url
    case deeplink
    case navigation
    case purchase
    case restore
    case close
    case closeAll
    case loadProducts
  }
  
  struct Action {
    let type: ActionType
    let parameters: [String: Any]?
  }
  
}
