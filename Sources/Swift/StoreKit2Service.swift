//
//  StoreKit2Service.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 18.04.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

import Foundation
import StoreKit
import Qonversion

@available(iOS 15.0, *)
@objc(QONStoreKit2Service)
public class StoreKit2Service: NSObject {
  
  private let mapper = PurchasesMapper()
  
  @objc public func syncTransactions() {
    Task.init {
      do {
        let allTransasctions: [Transaction] = await fetchTransactions(for: Transaction.all)
        let unfinishedTransasctions: [Transaction] = await fetchTransactions(for: Transaction.unfinished)
        let currentEntitlements: [Transaction] = await fetchTransactions(for: Transaction.currentEntitlements)
        
        let mixedTransactions: [Transaction] = allTransasctions + unfinishedTransasctions + currentEntitlements
        var uniqueTransactions: [UInt64: Transaction] = [:]
        mixedTransactions.forEach {
          if uniqueTransactions[$0.id] == nil {
            uniqueTransactions[$0.id] = $0
          }
        }
        
        let filteredTransactions = filter(transactions: Array(uniqueTransactions.values))
        let productIds: [String] = filteredTransactions.map { $0.productID }
        do {
          let products: [Product] = try await Product.products(for: Set(productIds))
          let mappedTransactions: [QONStoreKit2PurchaseModel] = await mapper.map(transactions: filteredTransactions, with: products)
          Qonversion.shared().handlePurchases(mappedTransactions)
        } catch {
          // store transactions
        }
      }
    }
  }
  
  func fetchTransactions(for type: Transaction.Transactions) async -> [Transaction] {
    var transasctions: [Transaction] = []
    for await transaction in type {
      switch transaction {
      case .verified(let verifiedTransaction):
        transasctions.append(verifiedTransaction)
      default:
        break
      }
    }
    
    return transasctions
  }
  
  func filter(transactions: [Transaction]) -> [Transaction] {
    let sortedTransactions = transactions.sorted(by: { $0.purchaseDate.compare($1.purchaseDate) == .orderedAscending })
    let groupedTransactions: [UInt64: [Transaction]] = group(transactions: transactions)
    let filteredTransactions = filterGroupedTransactions(groupedTransactions)
    
    return filteredTransactions
  }
  
  func group(transactions: [Transaction]) -> [UInt64: [Transaction]] {
    var resultMap: [UInt64: [Transaction]] = [:]
    for transaction in transactions {
      var transactionsByOriginalId = resultMap[transaction.originalID] ?? []
      transactionsByOriginalId.append(transaction)
      resultMap[transaction.originalID] = transactionsByOriginalId
    }
    
    return resultMap
  }
  
  func filterGroupedTransactions(_ transactions: [UInt64: [Transaction]]) -> [Transaction] {
    var result: [Transaction] = []
    for (_, transactions) in transactions {
      if transactions.count > 1 {
        var previousHandledProductId = ""
        
        for transaction in transactions {
          if previousHandledProductId != transaction.productID {
            result.append(transaction)
            previousHandledProductId = transaction.productID
          }
        }
      } else {
        result.append(contentsOf: transactions)
      }
    }
    
    return result
  }
}
