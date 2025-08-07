//
//  NetworkErrorHandlerInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 07.02.2024.
//

import Foundation

#if os(iOS)

protocol NetworkErrorHandlerInterface {
    
    func extractError(from response: URLResponse, body: Data) -> NoCodesError?
}

#endif
