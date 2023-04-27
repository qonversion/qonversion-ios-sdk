//
//  QonversionSwift.swift
//  
//
//  Created by Suren Sarkisyan on 27.04.2023.
//

import Foundation
@_exported import Qonversion

public class QonversionSwift {
  static public let shared = QonversionSwift()
  
  private var storeKitService: StoreKit2Service?
  
  init() {
    if #available(iOS 15.0, *) {
      self.storeKitService = StoreKit2Service()
    } else {
      // Fallback on earlier versions
    }
  }
  
  /// Contact us before you start using this function.
  /// Call this function to sync purchases if you are using StoreKit2.
  public func syncStoreKit2Purchases() {
    storeKitService?.syncTransactions()
  }
}
