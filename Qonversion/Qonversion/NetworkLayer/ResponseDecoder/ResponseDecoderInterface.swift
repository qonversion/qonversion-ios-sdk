//
//  ResponseDecoderInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 07.02.2024.
//

protocol ResponseDecoderInterface {
    func decode<T>(_ type: T.Type, from data: Data) throws -> T where T : Decodable
}
