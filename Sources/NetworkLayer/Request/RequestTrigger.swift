//
//  RequestTrigger.swift
//  Qonversion
//

import Foundation

/// The SDK flow that produced a request; travels in the `Trigger` header on
/// user and purchase requests so the backend can tell the entry points apart.
/// Values mirror the production SDK contract.
enum RequestTrigger: String {
    case initialization = "Init"
    case purchase = "Purchase"
    case products = "Products"
    case restore = "Restore"
    case syncHistoricalData = "SyncHistoricalData"
    case actualizePermissions = "ActualizePermissions"
    case identify = "Identify"
    case logout = "Logout"
    case userProperties = "UserProperties"
    case handleStoreKit2Transactions = "HandleStoreKit2Transactions"
}
