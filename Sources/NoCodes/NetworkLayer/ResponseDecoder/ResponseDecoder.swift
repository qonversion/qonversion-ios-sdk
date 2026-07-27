//
//  ResponseDecoder.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 07.02.2024.
//

import Foundation

// @unchecked: `decoder` is configured once in init and never mutated
// afterwards, so its `decode` calls are safe from any thread.
final class ResponseDecoder: ResponseDecoderInterface, @unchecked Sendable {
    let decoder: JSONDecoder
    
    init(decoder: JSONDecoder) {
        self.decoder = decoder
    }
    
    func decode<T>(_ type: T.Type, from data: Data) throws -> T where T : Decodable {
        try decoder.decode(type, from: data)
    }
}
