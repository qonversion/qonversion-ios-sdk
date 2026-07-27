//
//  NetworkProvider.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 02.02.2024.
//

import Foundation

// @unchecked: URLSession is thread-safe; no mutable state.
final class NetworkProvider: NetworkProviderInterface, @unchecked Sendable {
    let session: URLSession
    
    init(session: URLSession) {
        self.session = session
    }
    
    func send(request: URLRequest) async throws -> (Data, URLResponse) {
        return try await session.data(for: request)
    }
}
