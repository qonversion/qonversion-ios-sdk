//
//  ApiError.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 22.04.2024.
//

import Foundation

struct ApiError : Decodable {

    /// The backend error code. Absent from partial error bodies.
    let code: String?
    let message: String
    /// The backend error class. Absent from partial error bodies.
    let type: String?

    init(code: String?, message: String, type: String?) {
        self.code = code
        self.message = message
        self.type = type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decode(String.self, forKey: .message)
        // A body carrying only some of the fields must still yield what it
        // does carry: the code drives the typed error mapping.
        code = try? container.decodeIfPresent(String.self, forKey: .code)
        type = try? container.decodeIfPresent(String.self, forKey: .type)
    }

    private enum CodingKeys: String, CodingKey {
        case code
        case message
        case type
    }
}

struct ApiErrorWrapper : Decodable {

    let error: ApiError

    init(error: ApiError) {
        self.error = error
    }
}
