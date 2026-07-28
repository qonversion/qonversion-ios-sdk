//
//  AppTransactionReaderInterface.swift
//  Qonversion
//

import Foundation

/// Supplies the app version the user originally downloaded from the App Store.
protocol AppTransactionReaderInterface: Sendable {

    /// The original app version, or nil when the store does not report one.
    /// Never throws: an unknown version is a valid answer.
    func originalAppVersion() async -> String?
}
