//
//  ProductsService.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 18.04.2024.
//

import Foundation

final class ProductsService: ProductsServiceInterface {
    
    private let requestProcessor: RequestProcessorInterface
    private let internalConfig: InternalConfig
    
    init(requestProcessor: RequestProcessorInterface, internalConfig: InternalConfig) {
        self.requestProcessor = requestProcessor
        self.internalConfig = internalConfig
    }
    
    func productPermissions() async throws -> [String: [String]] {
        // The dashboard defines entitlements with their unlocking products;
        // the SDK needs the inverse: product -> entitlements it grants.
        let request = Request.entitlementDefinitions()
        do {
            let list: ListEnvelope<EntitlementDefinition> = try await requestProcessor.process(request: request, responseType: ListEnvelope<EntitlementDefinition>.self)

            var mapping: [String: [String]] = [:]
            for definition in list.data {
                for productId in definition.productIds {
                    mapping[productId, default: []].append(definition.id)
                }
            }
            return mapping
        } catch {
            throw QonversionError(type: .productPermissionsLoadingFailed, message: nil, error: error)
        }
    }

    func offerings(userId: String) async throws -> [Qonversion.Offering] {
        let request = Request.getOfferings(userId: userId)
        do {
            let list: ListEnvelope<Qonversion.Offering> = try await requestProcessor.process(request: request, responseType: ListEnvelope<Qonversion.Offering>.self)

            return list.data
        } catch {
            throw QonversionError(type: .offeringsLoadingFailed, message: nil, error: error)
        }
    }

    func products() async throws -> [Qonversion.Product] {
        let request = Request.getProducts()
        do {
            let list: ListEnvelope<Qonversion.Product> = try await requestProcessor.process(request: request, responseType: ListEnvelope<Qonversion.Product>.self)

            return list.data
        } catch {
            throw QonversionError(type: .productsLoadingFailed, message: nil, error: error)
        }
    }
    
}
