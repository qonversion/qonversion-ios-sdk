//
//  PurchasesService.swift
//  Qonversion
//

import Foundation

final class PurchasesService: PurchasesServiceInterface {

    private let requestProcessor: RequestProcessorInterface

    init(requestProcessor: RequestProcessorInterface) {
        self.requestProcessor = requestProcessor
    }

    func send(_ transaction: Qonversion.Transaction, userId: String) async throws {
        let appStoreData: RequestBodyDict = [
            "transaction_id": transaction.id ?? "",
            "original_transaction_id": transaction.originalId ?? "",
            "product_id": transaction.productId,
            // The signed-transaction jws proof travels in the receipt slot of
            // the purchase contract; ids next to it let the backend resolve
            // the transaction through the App Store Server API as well.
            "receipt": transaction.jws ?? "",
        ]
        let body: RequestBodyDict = [
            "price": transaction.price.map { "\($0)" } ?? "",
            "currency": transaction.currency?.identifier ?? "",
            "purchased": Int64(transaction.purchaseDate?.timeIntervalSince1970 ?? 0),
            "app_store_data": appStoreData,
        ]

        let request = Request.createPurchase(userId: userId, body: body)
        do {
            _ = try await requestProcessor.process(request: request, responseType: EmptyApiResponse.self)
        } catch {
            throw QonversionError(type: .purchaseReportingFailed, message: nil, error: error)
        }
    }
}
