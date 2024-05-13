//
//  Request.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 06.02.2024.
//

import Foundation

typealias RequestBodyDict = [String: AnyHashable]
typealias RequestBodyArray = [AnyHashable]

enum Request : Hashable {
    case getUser(id: String, endpoint: String = "v3/users/", type: RequestType = .get)
    case createUser(id: String, endpoint: String = "v3/users/", body: RequestBodyDict, type: RequestType = .post)
    case getProperties(userId: String, endpoint: String = "v3/users/%@/properties", type: RequestType = .get)
    case sendProperties(userId: String, endpoint: String = "v3/users/%@/properties", body: RequestBodyArray, type: RequestType = .post)
    case createDevice(userId: String, endpoint: String = "v3/device/", body: RequestBodyDict, type: RequestType = .post)
    case updateDevice(userId: String, endpoint: String = "v3/device/", body: RequestBodyDict, type: RequestType = .put)
    case appleSearchAds(userId: String, endpoint: String = "v3/appleads/", body: RequestBodyDict, type: RequestType = .post)
    case getProducts(userId: String, endpoint: String = "v3/products/", type: RequestType = .get)
    case getEntitlements(userId: String, endpoint: String = "v3/users/%@/entitlements", type: RequestType = .get)
    case getOfferings(userId: String, endpoint: String = "v3/offerings/", type: RequestType = .get)
    case remoteConfig(userId: String, contextKey: String?, endpoint: String = "v3/remote-config", type: RequestType = .get)
    case remoteConfigList(userId: String, contextKeys: [String], includeEmptyContextKey: Bool, endpoint: String = "v3/remote-configs", type: RequestType = .get)
    case allRemoteConfigList(userId: String, endpoint: String = "v3/remote-configs?all_context_keys=true", type: RequestType = .get)
    case attachUserToExperiment(userId: String, experimentId: String, groupId: String, endpoint: String = "v3/experiments/%@/users/%@", type: RequestType = .post)
    case detachUserFromExperiment(userId: String, experimentId: String, endpoint: String = "v3/experiments/%@/users/%@", type: RequestType = .delete)
    case attachUserToRemoteConfig(userId: String, remoteConfigId: String, endpoint: String = "v3/remote-configurations/%@/users/%@", type: RequestType = .post)
    case detachUserFromRemoteConfig(userId: String, remoteConfigId: String, endpoint: String = "v3/remote-configurations/%@/users/%@", type: RequestType = .delete)

    func convertToURLRequest(_ baseUrl: String) -> URLRequest? {
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
            return defaultRequest(urlString: endpoint + id, body: nil, type: type)

        case let .createUser(id, endpoint, body, type):
            return defaultRequest(urlString: endpoint + id, body: body, type: type)

        case let .getProperties(userId, endpoint, type):
            let urlString = String(format: endpoint, arguments: [userId])
            return defaultRequest(urlString: urlString, body: nil, type: type)
            
        case let .sendProperties(userId, endpoint, body, type):
            let urlString = String(format: endpoint, arguments: [userId])
            return defaultRequest(urlString: urlString, body: body, type: type)
            
        case let .createDevice(userId, endpoint, body, type):
            return defaultRequest(urlString: endpoint + userId, body: body, type: type)
            
        case let .updateDevice(userId, endpoint, body, type):
            return defaultRequest(urlString: endpoint + userId, body: body, type: type)
        
        case let .appleSearchAds(userId, endpoint, body, type):
            return defaultRequest(urlString: endpoint + userId, body: body, type: type)
        
        case let .getProducts(userId, endpoint, type):
            return defaultRequest(urlString: endpoint + userId, body: nil, type: type)
            
        case let .getEntitlements(userId, endpoint, type):
            let urlString = String(format: endpoint, arguments: [userId])
            return defaultRequest(urlString: urlString, body: nil, type: type)
        
        case let .getOfferings(userId, endpoint, type):
            return defaultRequest(urlString: endpoint + userId, body: nil, type: type)
            
        case let .remoteConfig(userId, contextKey, endpoint, type):
            var urlString = endpoint + "?user_id=" + userId
            if let contextKey = contextKey {
                urlString += "&context_key=" + contextKey
            }
            return defaultRequest(urlString: urlString, body: nil, type: type)

        case let .remoteConfigList(userId, contextKeys, includeEmptyContextKey, endpoint, type):
            var urlString = endpoint + "?user_id=" + userId + "&with_empty_context_key=" + (includeEmptyContextKey ? "true" : "false")
            for contextKey in contextKeys {
                urlString += "&context_key=" + contextKey
            }
            return defaultRequest(urlString: urlString, body: nil, type: type)

        case let .allRemoteConfigList(userId, endpoint, type):
            var urlString = endpoint + "&user_id=" + userId
            return defaultRequest(urlString: urlString, body: nil, type: type)

        case let .attachUserToRemoteConfig(userId, remoteConfigId, endpoint, type):
            let urlString = String(format: endpoint, arguments: [remoteConfigId, userId])
            return defaultRequest(urlString: urlString, body: nil, type: type)

        case let .detachUserFromRemoteConfig(userId, remoteConfigId, endpoint, type):
            let urlString = String(format: endpoint, arguments: [remoteConfigId, userId])
            return defaultRequest(urlString: urlString, body: nil, type: type)

        case let .attachUserToExperiment(userId, experimentId, groupId, endpoint, type):
            let urlString = String(format: endpoint, arguments: [experimentId, userId])
            return defaultRequest(urlString: urlString, body: ["group_id": groupId], type: type)

        case let .detachUserFromExperiment(userId, experimentId, endpoint, type):
            let urlString = String(format: endpoint, arguments: [experimentId, userId])
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
        case let .createUser(id, endpoint, body, type):
            hasher.combine("createUser")
            hasher.combine(id)
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
        case let .getProducts(userId, endpoint, type):
            hasher.combine("getProducts")
            hasher.combine(userId)
            hasher.combine(endpoint)
            hasher.combine(type)
        case let .getEntitlements(userId, endpoint, type):
            hasher.combine("getEntitlements")
            hasher.combine(userId)
            hasher.combine(endpoint)
            hasher.combine(type)
        case let .getOfferings(userId, endpoint, type):
            hasher.combine("getOfferings")
            hasher.combine(userId)
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
