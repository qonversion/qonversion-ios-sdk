//
//  EntitlementsService.swift
//  Qonversion
//

import Foundation

final class EntitlementsService: EntitlementsServiceInterface {

    private let requestProcessor: RequestProcessorInterface

    init(requestProcessor: RequestProcessorInterface) {
        self.requestProcessor = requestProcessor
    }

    func entitlements(userId: String) async throws -> [Qonversion.Entitlement] {
        let request = Request.entitlements(userId: userId)
        do {
            let list: Qonversion.EntitlementsList = try await requestProcessor.process(request: request, responseType: Qonversion.EntitlementsList.self)

            return list.data
        } catch {
            throw QonversionError(type: .entitlementsLoadingFailed, message: nil, error: error)
        }
    }
}
