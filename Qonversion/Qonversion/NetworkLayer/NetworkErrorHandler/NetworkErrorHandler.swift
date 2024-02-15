//
//  NetworkErrorHandler.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 07.02.2024.
//

class NetworkErrorHandler: NetworkErrorHandlerInterface {
    
    func extractError(from response: URLResponse) -> Error? {
        guard let httpResponse = response as? HTTPURLResponse else { return nil }
        
        let statusCode = httpResponse.statusCode
    }
    
}
