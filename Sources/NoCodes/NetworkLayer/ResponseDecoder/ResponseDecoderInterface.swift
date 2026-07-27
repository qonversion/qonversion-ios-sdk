//
//  ResponseDecoderInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 07.02.2024.
//

import Foundation

protocol ResponseDecoderInterface: Sendable {
    func decode<T>(_ type: T.Type, from data: Data) throws -> T where T : Decodable
}
