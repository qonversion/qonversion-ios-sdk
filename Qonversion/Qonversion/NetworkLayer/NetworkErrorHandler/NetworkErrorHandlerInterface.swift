//
//  NetworkErrorHandlerInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 07.02.2024.
//

protocol NetworkErrorHandlerInterface {
    
    func extractError(from response: URLResponse) -> Error?
    
}
