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
    case getPreloadScreens(endpoint: String = "v3/screens?preload=true", type: RequestType = .get)
    case sendScreenEvents(uid: String, body: [[String: AnyHashable]], endpoint: String = "v3/users/%@/screen-events", type: RequestType = .post)
    
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
            let encodedId: String = Request.encodedPathComponent(id)
            return defaultRequest(urlString: endpoint + encodedId, body: nil, type: type)
        case let .getScreenByContextKey(contextKey, endpoint, type):
            let encodedContextKey: String = Request.encodedPathComponent(contextKey)
            let urlString: String = String(format: endpoint, arguments: [encodedContextKey])
            return defaultRequest(urlString: urlString, body: nil, type: type)
        case let .getPreloadScreens(endpoint, type):
            return defaultRequest(urlString: endpoint, body: nil, type: type)
        case let .sendScreenEvents(uid, body, endpoint, type):
            let encodedUid: String = Request.encodedPathComponent(uid)
            let urlString: String = String(format: endpoint, arguments: [encodedUid])
            return defaultRequest(urlString: urlString, body: ["events": body], type: type)
        }
    }

    /// Screen ids, context keys and user ids are caller-supplied and go into the
    /// path, so they must be escaped: an unescaped `/`, `?` or `#` would silently
    /// retarget the request.
    static func encodedPathComponent(_ value: String) -> String {
        return value.addingPercentEncoding(withAllowedCharacters: .urlPathComponentAllowed) ?? value
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
        case let .sendScreenEvents(uid, _, endpoint, type):
            hasher.combine("sendScreenEvents")
            hasher.combine(uid)
            hasher.combine(endpoint)
            hasher.combine(type)
        }
    }
}
