//
//  QonversionSwift.swift
//  
//
//  Created by Suren Sarkisyan on 27.04.2023.
//

import Foundation
import Qonversion

@available(iOS 15.0, *)
public class QonversionSwift {
    static public let shared = QonversionSwift(storeKitService: StoreKit2Service())
    
    private let storeKitService: StoreKit2Service
    
    init(storeKitService: StoreKit2Service) {
        self.storeKitService = storeKitService
    }
    
    /// Contact us before you start using this function.
    /// Call this function to sync purchases if you are using StoreKit2.
    public func syncStoreKit2Purchases() {
        storeKitService.syncTransactions()
    }
}
