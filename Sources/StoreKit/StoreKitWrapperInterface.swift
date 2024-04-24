//
//  StoreKitWrapperInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 21.02.2024.
//

import Foundation
import StoreKit

protocol StoreKitWrapperInterface {
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    func purchase(product: StoreKit.Product) async throws -> StoreKit.Transaction
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
    func products(for ids:[String]) async throws -> [StoreKit.Product]
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    func currentEntitlements() async -> [StoreKit.Transaction]
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    func restore() async throws
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    func fetchAll() async -> [StoreKit.Transaction]
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    func fetchUnfinished() async -> [StoreKit.Transaction]
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    func finish(transaction: StoreKit.Transaction) async
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    func subscribe() async -> [StoreKit.Transaction]
        
    @available(iOS 16.0, visionOS 1.0, *)
    @available(macOS, unavailable)
    @available(watchOS, unavailable)
    @available(tvOS, unavailable)
    func presentOfferCodeRedeemSheet(in scene: UIWindowScene) async throws
}
