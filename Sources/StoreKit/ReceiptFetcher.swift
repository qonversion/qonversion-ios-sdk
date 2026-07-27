//
//  ReceiptFetcher.swift
//  Qonversion
//

import Foundation

protocol ReceiptFetcherInterface: Sendable {

    /// The base64-encoded App Store receipt of the app, if present. The only
    /// proof of purchase available on the StoreKit 1 path.
    func appStoreReceipt() -> String?
}

final class ReceiptFetcher: ReceiptFetcherInterface {

    func appStoreReceipt() -> String? {
        guard let url: URL = Bundle.main.appStoreReceiptURL,
              let data: Data = try? Data(contentsOf: url) else {
            return nil
        }

        return data.base64EncodedString()
    }
}
