//
//  Request.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 06.02.2024.
//

import Foundation

typealias RequestBody = [String: AnyHashable]

enum Request : Hashable {
    // All requests are just examples and should be overridden
    case getUser(id: String, endpoint: String = "v3/users/", type: RequestType = .get)
    case createUser(id: String, endpoint: String = "v3/users/", body: RequestBody, type: RequestType = .post)
    case entitlements(userId: String, endpoint: String = "v3/users/{user_id}/entitlements", type: RequestType = .post)
    case getProperties(userId: String, endpoint: String = "v3/users/{user_id}/properties", type: RequestType = .get)

    func convertToURLRequest(_ baseUrl: String) -> URLRequest? {
        func defaultRequest(urlString: String, body: RequestBody?, type: RequestType) -> URLRequest? {
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
            let url = endpoint.replacingOccurrences(of: "{user_id}", with: userId)
            return defaultRequest(urlString: url, body: nil, type: type)

        case let .getProperties(userId, endpoint, type):
            let url = endpoint.replacingOccurrences(of: "{user_id}", with: userId)
            return defaultRequest(urlString: url, body: nil, type: type)
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
        }
    }
}
