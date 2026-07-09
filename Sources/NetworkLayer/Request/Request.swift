//
//  Request.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 06.02.2024.
//

import Foundation

typealias RequestBodyDict = [String: AnyHashable]
typealias RequestBodyArray = [AnyHashable]

extension Request {

    /// Case discriminator used to declare which requests are eligible for
    /// the offline replay.
    enum Kind {
        case getUser
        case createUser
        case getIdentity
        case createIdentity
        case entitlements
        case createPurchase
        case signPromoOffer
        case getProperties
        case sendProperties
        case createDevice
        case updateDevice
        case appleSearchAds
        case getProducts
        case entitlementDefinitions
        case remoteConfig
        case remoteConfigList
        case allRemoteConfigList
        case attachUserToExperiment
        case detachUserFromExperiment
        case attachUserToRemoteConfig
        case detachUserFromRemoteConfig
    }

    /// Identifies the payload for the offline replay dedup: the same failed
    /// purchase (by transaction id) or per-user device/attribution update
    /// never queues twice.
    var replayDedupKey: String? {
        switch self {
        case let .createPurchase(userId, _, body, _):
            let storeData = body["store_data"] as? RequestBodyDict
            let transactionId = storeData?["transaction_id"] as? String ?? ""
            // Without a transaction id the key would collapse distinct
            // purchases into one — disable dedup instead.
            guard !transactionId.isEmpty else { return nil }
            return "createPurchase-\(userId)-\(transactionId)"
        case let .createDevice(userId, _, _, _):
            return "createDevice-\(userId)"
        case let .updateDevice(userId, _, _, _):
            return "updateDevice-\(userId)"
        case let .appleSearchAds(userId, _, _, _):
            return "appleSearchAds-\(userId)"
        default:
            return nil
        }
    }

    var kind: Kind {
        switch self {
        case .getUser: return .getUser
        case .createUser: return .createUser
        case .getIdentity: return .getIdentity
        case .createIdentity: return .createIdentity
        case .entitlements: return .entitlements
        case .createPurchase: return .createPurchase
        case .signPromoOffer: return .signPromoOffer
        case .getProperties: return .getProperties
        case .sendProperties: return .sendProperties
        case .createDevice: return .createDevice
        case .updateDevice: return .updateDevice
        case .appleSearchAds: return .appleSearchAds
        case .getProducts: return .getProducts
        case .entitlementDefinitions: return .entitlementDefinitions
        case .remoteConfig: return .remoteConfig
        case .remoteConfigList: return .remoteConfigList
        case .allRemoteConfigList: return .allRemoteConfigList
        case .attachUserToExperiment: return .attachUserToExperiment
        case .detachUserFromExperiment: return .detachUserFromExperiment
        case .attachUserToRemoteConfig: return .attachUserToRemoteConfig
        case .detachUserFromRemoteConfig: return .detachUserFromRemoteConfig
        }
    }
}

enum Request : Hashable {
    case getUser(id: String, endpoint: String = "v4/users/", type: RequestType = .get)
    // The uid travels in the body ("id") — v4 style.
    case createUser(endpoint: String = "v4/users", body: RequestBodyDict, type: RequestType = .post)
    case getIdentity(externalId: String, endpoint: String = "v4/identities/", type: RequestType = .get)
    // The external id and uid travel in the body — v4 style.
    case createIdentity(endpoint: String = "v4/identities", body: RequestBodyDict, type: RequestType = .post)
    case entitlements(userId: String, endpoint: String = "v4/users/%@/entitlements", type: RequestType = .get)
    case createPurchase(userId: String, endpoint: String = "v4/users/%@/purchases", body: RequestBodyDict, type: RequestType = .post)
    case signPromoOffer(userId: String, offerId: String, endpoint: String = "v4/users/%@/offers/%@/signatures", body: RequestBodyDict, type: RequestType = .post)
    case getProperties(userId: String, endpoint: String = "v4/users/%@/properties", type: RequestType = .get)
    case sendProperties(userId: String, endpoint: String = "v4/users/%@/properties", body: RequestBodyDict, type: RequestType = .post)
    case createDevice(userId: String, endpoint: String = "v4/users/%@/device", body: RequestBodyDict, type: RequestType = .post)
    case updateDevice(userId: String, endpoint: String = "v4/users/%@/device", body: RequestBodyDict, type: RequestType = .put)
    case appleSearchAds(userId: String, endpoint: String = "v4/users/%@/attribution", body: RequestBodyDict, type: RequestType = .post)
    case getProducts(endpoint: String = "v4/products", type: RequestType = .get)
    case entitlementDefinitions(endpoint: String = "v4/entitlements", type: RequestType = .get)
    case remoteConfig(userId: String, contextKey: String?, endpoint: String = "v4/remote-config", type: RequestType = .get)
    case remoteConfigList(userId: String, contextKeys: [String], includeEmptyContextKey: Bool, endpoint: String = "v4/remote-configs", type: RequestType = .get)
    case allRemoteConfigList(userId: String, endpoint: String = "v4/remote-configs?all_context_keys=true", type: RequestType = .get)
    case attachUserToExperiment(userId: String, experimentId: String, groupId: String, endpoint: String = "v4/experiments/%@/users/%@", type: RequestType = .post)
    case detachUserFromExperiment(userId: String, experimentId: String, endpoint: String = "v4/experiments/%@/users/%@", type: RequestType = .delete)
    case attachUserToRemoteConfig(userId: String, remoteConfigId: String, endpoint: String = "v4/remote-configurations/%@/users/%@", type: RequestType = .post)
    case detachUserFromRemoteConfig(userId: String, remoteConfigId: String, endpoint: String = "v4/remote-configurations/%@/users/%@", type: RequestType = .delete)

    func convertToURLRequest(_ baseUrl: String) -> URLRequest? {
        // RFC 3986 unreserved characters: everything else in a dynamic path
        // or query value gets percent-encoded, so ids like "a&b" or "x+y"
        // cannot corrupt the URL structure.
        func escaped(_ value: String) -> String {
            let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
            return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
        }

        func defaultRequest(urlString: String, body: Any?, type: RequestType) -> URLRequest? {
            guard let url = URL(string: baseUrl + urlString) else { return nil }
            var request = URLRequest(url: url)
            request.httpMethod = type.rawValue
            if let body {
                request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            }

            return request
        }

        switch self {
        case let .getUser(id, endpoint, type):
            return defaultRequest(urlString: endpoint + escaped(id), body: nil, type: type)

        case let .createUser(endpoint, body, type):
            return defaultRequest(urlString: endpoint, body: body, type: type)

        case let .getIdentity(externalId, endpoint, type):
            return defaultRequest(urlString: endpoint + escaped(externalId), body: nil, type: type)

        case let .createIdentity(endpoint, body, type):
            return defaultRequest(urlString: endpoint, body: body, type: type)

        case let .entitlements(userId, endpoint, type):
            let urlString = String(format: endpoint, arguments: [escaped(userId)])
            return defaultRequest(urlString: urlString, body: nil, type: type)

        case let .createPurchase(userId, endpoint, body, type):
            let urlString = String(format: endpoint, arguments: [escaped(userId)])
            return defaultRequest(urlString: urlString, body: body, type: type)

        case let .signPromoOffer(userId, offerId, endpoint, body, type):
            let urlString = String(format: endpoint, arguments: [escaped(userId), escaped(offerId)])
            return defaultRequest(urlString: urlString, body: body, type: type)

        case let .getProperties(userId, endpoint, type):
            let urlString = String(format: endpoint, arguments: [escaped(userId)])
            return defaultRequest(urlString: urlString, body: nil, type: type)
            
        case let .sendProperties(userId, endpoint, body, type):
            let urlString = String(format: endpoint, arguments: [escaped(userId)])
            return defaultRequest(urlString: urlString, body: body, type: type)
            
        case let .createDevice(userId, endpoint, body, type):
            let urlString = String(format: endpoint, arguments: [escaped(userId)])
            return defaultRequest(urlString: urlString, body: body, type: type)

        case let .updateDevice(userId, endpoint, body, type):
            let urlString = String(format: endpoint, arguments: [escaped(userId)])
            return defaultRequest(urlString: urlString, body: body, type: type)

        case let .appleSearchAds(userId, endpoint, body, type):
            let urlString = String(format: endpoint, arguments: [escaped(userId)])
            return defaultRequest(urlString: urlString, body: body, type: type)
        
        case let .getProducts(endpoint, type):
            return defaultRequest(urlString: endpoint, body: nil, type: type)

        case let .entitlementDefinitions(endpoint, type):
            return defaultRequest(urlString: endpoint, body: nil, type: type)
            
        case let .remoteConfig(userId, contextKey, endpoint, type):
            var urlString = endpoint + "?user_id=" + escaped(userId)
            if let contextKey = contextKey {
                urlString += "&context_key=" + escaped(contextKey)
            }
            return defaultRequest(urlString: urlString, body: nil, type: type)

        case let .remoteConfigList(userId, contextKeys, includeEmptyContextKey, endpoint, type):
            var urlString = endpoint + "?user_id=" + escaped(userId) + "&with_empty_context_key=" + (includeEmptyContextKey ? "true" : "false")
            for contextKey in contextKeys {
                urlString += "&context_key=" + escaped(contextKey)
            }
            return defaultRequest(urlString: urlString, body: nil, type: type)

        case let .allRemoteConfigList(userId, endpoint, type):
            var urlString = endpoint + "&user_id=" + escaped(userId)
            return defaultRequest(urlString: urlString, body: nil, type: type)

        case let .attachUserToRemoteConfig(userId, remoteConfigId, endpoint, type):
            let urlString = String(format: endpoint, arguments: [escaped(remoteConfigId), escaped(userId)])
            return defaultRequest(urlString: urlString, body: nil, type: type)

        case let .detachUserFromRemoteConfig(userId, remoteConfigId, endpoint, type):
            let urlString = String(format: endpoint, arguments: [escaped(remoteConfigId), escaped(userId)])
            return defaultRequest(urlString: urlString, body: nil, type: type)

        case let .attachUserToExperiment(userId, experimentId, groupId, endpoint, type):
            let urlString = String(format: endpoint, arguments: [escaped(experimentId), escaped(userId)])
            return defaultRequest(urlString: urlString, body: ["group_id": groupId], type: type)

        case let .detachUserFromExperiment(userId, experimentId, endpoint, type):
            let urlString = String(format: endpoint, arguments: [escaped(experimentId), escaped(userId)])
            return defaultRequest(urlString: urlString, body: nil, type: type)
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case let .getUser(id, endpoint, type):
            hasher.combine("getUser")
            hasher.combine(id)
            hasher.combine(endpoint)
            hasher.combine(type)
        case let .createUser(endpoint, body, type):
            hasher.combine("createUser")
            hasher.combine(endpoint)
            hasher.combine(body)
            hasher.combine(type)
        case let .getIdentity(externalId, endpoint, type):
            hasher.combine("getIdentity")
            hasher.combine(externalId)
            hasher.combine(endpoint)
            hasher.combine(type)
        case let .createIdentity(endpoint, body, type):
            hasher.combine("createIdentity")
            hasher.combine(endpoint)
            hasher.combine(body)
            hasher.combine(type)
        case let .entitlements(userId, endpoint, type):
            hasher.combine("entitlements")
            hasher.combine(userId)
            hasher.combine(endpoint)
            hasher.combine(type)
        case let .signPromoOffer(userId, offerId, endpoint, body, type):
            hasher.combine("signPromoOffer")
            hasher.combine(userId)
            hasher.combine(offerId)
            hasher.combine(endpoint)
            hasher.combine(body)
            hasher.combine(type)
        case let .createPurchase(userId, endpoint, body, type):
            hasher.combine("createPurchase")
            hasher.combine(userId)
            hasher.combine(endpoint)
            hasher.combine(body)
            hasher.combine(type)
        case let .getProperties(userId, endpoint, type):
            hasher.combine("getProperties")
            hasher.combine(userId)
            hasher.combine(endpoint)
            hasher.combine(type)
        case let .sendProperties(userId, endpoint, body, type):
            hasher.combine("sendProperties")
            hasher.combine(userId)
            hasher.combine(endpoint)
            hasher.combine(body)
            hasher.combine(type)
        case let .createDevice(userId, endpoint, body, type):
            hasher.combine("createDevice")
            hasher.combine(userId)
            hasher.combine(endpoint)
            hasher.combine(body)
            hasher.combine(type)
        case let .updateDevice(userId, endpoint, body, type):
            hasher.combine("updateDevice")
            hasher.combine(userId)
            hasher.combine(endpoint)
            hasher.combine(body)
            hasher.combine(type)
        case let .appleSearchAds(userId, endpoint, body, type):
            hasher.combine("appleSearchAds")
            hasher.combine(userId)
            hasher.combine(endpoint)
            hasher.combine(body)
            hasher.combine(type)
        case let .getProducts(endpoint, type):
            hasher.combine("getProducts")
            hasher.combine(endpoint)
            hasher.combine(type)
        case let .entitlementDefinitions(endpoint, type):
            hasher.combine("entitlementDefinitions")
            hasher.combine(endpoint)
            hasher.combine(type)
        case let .remoteConfig(userId, contextKey, endpoint, type):
            hasher.combine("remoteConfig")
            hasher.combine(userId)
            hasher.combine(contextKey)
            hasher.combine(endpoint)
            hasher.combine(type)
        case let .remoteConfigList(userId, contextKeys, includeEmptyContextKey, endpoint, type):
            hasher.combine("remoteConfigList")
            hasher.combine(userId)
            hasher.combine(contextKeys)
            hasher.combine(includeEmptyContextKey)
            hasher.combine(endpoint)
            hasher.combine(type)
        case let .allRemoteConfigList(userId, endpoint, type):
            hasher.combine("allRemoteConfigList")
            hasher.combine(userId)
            hasher.combine(endpoint)
            hasher.combine(type)
        case let .attachUserToRemoteConfig(userId, remoteConfigId, endpoint, type):
            hasher.combine("attachUserToRemoteConfig")
            hasher.combine(userId)
            hasher.combine(remoteConfigId)
            hasher.combine(endpoint)
            hasher.combine(type)
        case let .detachUserFromRemoteConfig(userId, remoteConfigId, endpoint, type):
            hasher.combine("detachUserFromRemoteConfig")
            hasher.combine(userId)
            hasher.combine(remoteConfigId)
            hasher.combine(endpoint)
            hasher.combine(type)
        case let .attachUserToExperiment(userId, experimentId, groupId, endpoint, type):
            hasher.combine("attachUserToExperiment")
            hasher.combine(userId)
            hasher.combine(experimentId)
            hasher.combine(groupId)
            hasher.combine(endpoint)
            hasher.combine(type)
        case let .detachUserFromExperiment(userId, experimentId, endpoint, type):
            hasher.combine("detachUserFromExperiment")
            hasher.combine(userId)
            hasher.combine(experimentId)
            hasher.combine(endpoint)
            hasher.combine(type)
        }
    }
}
