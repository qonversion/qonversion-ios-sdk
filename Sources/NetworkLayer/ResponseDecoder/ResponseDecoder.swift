//
//  ResponseDecoder.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 07.02.2024.
//

import Foundation

// @unchecked: the JSONDecoder is only read after init.
final class ResponseDecoder: ResponseDecoderInterface, @unchecked Sendable {
    let decoder: JSONDecoder
    
    init(decoder: JSONDecoder) {
        self.decoder = decoder
    }
    
    func decode<T>(_ type: T.Type, from data: Data) throws -> T where T : Decodable {
        try decoder.decode(type, from: data)
    }
}
