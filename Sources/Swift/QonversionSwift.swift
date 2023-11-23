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
  
  private var storeKitService: StoreKit2ServiceInterface?
  
  init() {
    if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
      self.storeKitService = StoreKit2Service()
    }
  }
  
  /// Contact us before you start using this function.
  /// Call this function to sync purchases if you are using StoreKit2.
  public func syncStoreKit2Purchases() {
    if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
      Task.init {
        try? await storeKitService?.syncTransactions()
      }
    }
  }
  
  /// Contact us before you start using this function.
  /// Call this function to sync purchases if you are using StoreKit2.
  @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
  public func syncStoreKit2Transactions() async {
    try? await storeKitService?.syncTransactions()
  }
  
  /// Call this function to sync StoreKit2 transaction with Qonversion.
  /// - Parameters:
  ///   - transaction: StoreKit2 transaction
  @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
  public func handleTransaction(_ transaction: Transaction) async {
    try? await storeKitService?.handleTransaction(transaction)
  }
  
  /// Call this function to sync StoreKit2 transactions with Qonversion.
  /// - Parameters:
  ///   - transactions: an array of StoreKit2 transactions
  @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
  public func handleTransactions(_ transactions: [Transaction]) async {
    try? await storeKitService?.handleTransactions(transactions)
  }
}
