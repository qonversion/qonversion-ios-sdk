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
    case entitlements(userId: String, endpoint: String = "v3/users/%@/entitlements", type: RequestType = .post)
    case getProperties(userId: String, endpoint: String = "v3/users/%@/properties", type: RequestType = .get)
    case sendProperties(userId: String, endpoint: String = "v3/users/%@/properties", body: RequestBodyArray, type: RequestType = .post)
    case createDevice(userId: String, endpoint: String = "v3/device/", body: RequestBodyDict, type: RequestType = .post)
    case updateDevice(userId: String, endpoint: String = "v3/device/", body: RequestBodyDict, type: RequestType = .put)
    case appleSearchAds(userId: String, endpoint: String = "v3/appleads/", body: RequestBodyDict, type: RequestType = .post)

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

        case let .entitlements(userId, endpoint, type):
            let urlString = String(format: endpoint, arguments: [userId])
            return defaultRequest(urlString: urlString, body: nil, type: type)

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
        case let .entitlements(userId, endpoint, type):
            hasher.combine("entitlements")
            hasher.combine(userId)
            hasher.combine(endpoint)
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
        }
    }
}
