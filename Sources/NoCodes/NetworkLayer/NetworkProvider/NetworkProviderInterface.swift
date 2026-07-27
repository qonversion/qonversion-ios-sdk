//
//  NetworkProviderInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 07.02.2024.
//

import Foundation

protocol NetworkProviderInterface {
    func send(request: URLRequest) async throws -> (Data, URLResponse)
}
