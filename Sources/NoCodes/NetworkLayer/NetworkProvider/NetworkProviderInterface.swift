//
//  NetworkProviderInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 07.02.2024.
//

import Foundation

protocol NetworkProviderInterface: Sendable {
    func send(request: URLRequest) async throws -> (Data, URLResponse)
}
