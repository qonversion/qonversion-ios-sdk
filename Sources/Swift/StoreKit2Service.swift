//
//  StoreKit2Service.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 18.04.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

import Foundation
import StoreKit
@_exported import Qonversion

protocol StoreKit2ServiceInterface {
  
  @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
  func syncTransactions() async throws
  
  @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
  func handleTransaction(_ transaction: Transaction) async throws
  
  @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
  func handleTransactions(_ transactions: [Transaction]) async throws
}

@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public class StoreKit2Service: StoreKit2ServiceInterface {
  
  let mapper = PurchasesMapper()
  
  func syncTransactions() async throws {
      let filteredTransactions = await fetchAllFilteredTransactions()
      let productIds: [String] = filteredTransactions.map { $0.productID }
      try await handleTransactions(filteredTransactions, for: productIds)
  }
  
  func handleTransaction(_ transaction: Transaction) async throws {
    try await handleTransactions([transaction], for: [transaction.productID])
  }
  
  func handleTransactions(_ transactions: [Transaction]) async throws {
    let productIds: [String] = transactions.map { $0.productID }
    try await handleTransactions(transactions, for: productIds)
  }
  
  // MARK: - Private
  
  private func handleTransactions(_ transactions: [Transaction], for productIds: [String]) async throws {
    let products: [Product] = try await Product.products(for: Set(productIds))
    let mappedTransactions: [Qonversion.StoreKit2PurchaseModel] = await mapper.map(transactions: transactions, with: products)
    try await Qonversion.shared().handlePurchases(mappedTransactions)
  }
  
  @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
  private func fetchAllFilteredTransactions() async -> [Transaction] {
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
    
    return filteredTransactions
  }
  
  @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
  private func fetchTransactions(for type: Transaction.Transactions) async -> [Transaction] {
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
  
  @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
  private func filter(transactions: [Transaction]) -> [Transaction] {
    let sortedTransactions = transactions.sorted(by: { $0.purchaseDate.compare($1.purchaseDate) == .orderedAscending })
    let groupedTransactions: [UInt64: [Transaction]] = group(transactions: sortedTransactions)
    let filteredTransactions = filterGroupedTransactions(groupedTransactions)
    
    return filteredTransactions
  }
  
  @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
  private func group(transactions: [Transaction]) -> [UInt64: [Transaction]] {
    var resultMap: [UInt64: [Transaction]] = [:]
    for transaction in transactions {
      var transactionsByOriginalId = resultMap[transaction.originalID] ?? []
      transactionsByOriginalId.append(transaction)
      resultMap[transaction.originalID] = transactionsByOriginalId
    }
    
    return resultMap
  }
  
  @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
  private func filterGroupedTransactions(_ transactions: [UInt64: [Transaction]]) -> [Transaction] {
    var result: [Transaction] = []
    for (_, transactions) in transactions {
      var previousHandledProductId = ""
      
      for transaction in transactions {
        // here we detect another product purchase
        if previousHandledProductId != transaction.productID {
          result.append(transaction)
          previousHandledProductId = transaction.productID
        }
      }
    }
    
    return result
  }
}
