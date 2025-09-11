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
    case getScreen(id: String, endpoint: String = "v3/screens/", type: RequestType = .get)
    case getScreenByContextKey(contextKey: String, endpoint: String = "v3/contexts/%@/screens", type: RequestType = .get)
    case getPreloadScreens(endpoint: String = "v3/screens/preload", type: RequestType = .get)
    
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
        case let .getScreen(id, endpoint, type):
            return defaultRequest(urlString: endpoint + id, body: nil, type: type)
        case let .getScreenByContextKey(contextKey, endpoint, type):
            let urlString = String(format: endpoint, arguments: [contextKey])
            return defaultRequest(urlString: urlString, body: nil, type: type)
        case let .getPreloadScreens(endpoint, type):
            return defaultRequest(urlString: endpoint, body: nil, type: type)
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case let .getScreen(id, endpoint, type):
            hasher.combine("getScreen")
            hasher.combine(id)
            hasher.combine(endpoint)
            hasher.combine(type)
        case let .getScreenByContextKey(contextKey, endpoint, type):
            hasher.combine("getScreenByContextKey")
            hasher.combine(contextKey)
            hasher.combine(endpoint)
            hasher.combine(type)
        case let .getPreloadScreens(endpoint, type):
            hasher.combine("getPreloadScreens")
            hasher.combine(endpoint)
            hasher.combine(type)
        }
    }
}
