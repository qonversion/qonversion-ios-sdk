//
//  RequestProcessorInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 07.02.2024.
//

protocol RequestProcessorInterface {
    @discardableResult
    func process<T>(request: Request, responseType: T.Type) async throws -> T where T : Decodable
}
