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
    case getScreen(id: String, endpoint: String = "v2/screens/", type: RequestType = .get)
    
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
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case let .getScreen(id, endpoint, type):
            hasher.combine("geScreen")
            hasher.combine(id)
            hasher.combine(endpoint)
            hasher.combine(type)
        }
    }
}
