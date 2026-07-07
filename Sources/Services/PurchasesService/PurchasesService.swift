//
//  PurchasesService.swift
//  Qonversion
//

import Foundation

/// Wire shape of the backend-signed promotional offer.
struct PromoOfferSignatureResponse: Decodable {

    let keyIdentifier: String
    let signature: String
    let nonce: String
    let timestamp: String

    private enum CodingKeys: String, CodingKey {
        case keyIdentifier = "key_identifier"
        case signature
        case nonce
        case timestamp
    }

    init(keyIdentifier: String, signature: String, nonce: String, timestamp: String) {
        self.keyIdentifier = keyIdentifier
        self.signature = signature
        self.nonce = nonce
        self.timestamp = timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyIdentifier = try container.decode(String.self, forKey: .keyIdentifier)
        signature = try container.decode(String.self, forKey: .signature)
        nonce = try container.decode(String.self, forKey: .nonce)
        timestamp = try container.decode(String.self, forKey: .timestamp)
    }
}

final class PurchasesService: PurchasesServiceInterface {

    private let requestProcessor: RequestProcessorInterface
    private let appBundleId: String

    init(requestProcessor: RequestProcessorInterface, appBundleId: String) {
        self.requestProcessor = requestProcessor
        self.appBundleId = appBundleId
    }

    func send(_ transaction: Qonversion.Transaction, userId: String, options: Qonversion.PurchaseOptions?) async throws {
        let appStoreData: RequestBodyDict = [
            "transaction_id": transaction.id ?? "",
            "original_transaction_id": transaction.originalId ?? "",
            "product_id": transaction.productId,
            // The signed-transaction jws proof travels in the receipt slot of
            // the purchase contract; ids next to it let the backend resolve
            // the transaction through the App Store Server API as well.
            "receipt": transaction.jws ?? "",
        ]
        var body: RequestBodyDict = [
            "price": transaction.price.map { "\($0)" } ?? "",
            "currency": transaction.currency?.identifier ?? "",
            "purchased": Int64(transaction.purchaseDate?.timeIntervalSince1970 ?? 0),
            "app_store_data": appStoreData,
        ]
        if let contextKeys = options?.contextKeys, !contextKeys.isEmpty {
            body["context_keys"] = contextKeys
        }
        if let screenUid = options?.screenUid {
            body["screen_uid"] = screenUid
        }

        let request = Request.createPurchase(userId: userId, body: body)
        do {
            _ = try await requestProcessor.process(request: request, responseType: EmptyApiResponse.self)
        } catch {
            throw QonversionError(type: .purchaseReportingFailed, message: nil, error: error)
        }
    }

    func promotionalOffer(userId: String, offerId: String, productStoreId: String) async throws -> Qonversion.PromotionalOffer {
        let body: RequestBodyDict = [
            "product": productStoreId,
            "app_account_token": userId,
            "app_bundle_id": appBundleId,
        ]
        let request = Request.signPromoOffer(userId: userId, offerId: offerId, body: body)

        let response: PromoOfferSignatureResponse
        do {
            response = try await requestProcessor.process(request: request, responseType: PromoOfferSignatureResponse.self)
        } catch {
            throw QonversionError(type: .promoOfferSigningFailed, message: nil, error: error)
        }

        guard let nonce = UUID(uuidString: response.nonce),
              let signature = Data(base64Encoded: response.signature),
              let timestamp = Int(response.timestamp) else {
            throw QonversionError(type: .promoOfferSigningFailed, message: "Malformed signature response")
        }

        return Qonversion.PromotionalOffer(
            offerId: offerId,
            keyId: response.keyIdentifier,
            nonce: nonce,
            signature: signature,
            timestamp: timestamp
        )
    }
}
