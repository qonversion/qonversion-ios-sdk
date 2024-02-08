//
//  NetworkProvider.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 02.02.2024.
//

class NetworkProvider: NetworkProviderInterface {
    let session: URLSession
    
    init(session: URLSession) {
        self.session = session
    }
    
    func send(request: URLRequest) async throws -> (Data, URLResponse) {
        return try await session.data(for: request)
    }
    
}
