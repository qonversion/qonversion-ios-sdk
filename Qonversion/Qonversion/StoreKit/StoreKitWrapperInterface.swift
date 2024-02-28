//
//  StoreKitWrapperInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 21.02.2024.
//

import Foundation
import StoreKit

protocol StoreKitWrapperInterface {
    
    @available(iOS 15.0, *)
    func products(for ids:[String]) async throws -> [Product]
    
    @available(iOS 15.0, *)
    func currentEntitlements() async -> [Transaction]
    
    @available(iOS 15.0, *)
    func restore() async throws
    
    @available(iOS 15.0, *)
    func fetchAll() async -> [Transaction]
    
    @available(iOS 15.0, *)
    func fetchUnfinished() async -> [Transaction]
    
    @available(iOS 15.0, *)
    func finish(transaction: Transaction) async
    
    @available(iOS 15.0, *)
    func subscribe() async -> [Transaction]
        
    @available(iOS 16.0, *)
    func presentOfferCodeRedeemSheet(in scene: UIWindowScene) async throws
    
}
