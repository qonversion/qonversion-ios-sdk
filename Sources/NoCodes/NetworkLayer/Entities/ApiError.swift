//
//  ApiError.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 22.04.2024.
//

import Foundation

struct ApiError : Decodable {

    let code: String
    let message: String
    let type: String

    init(code: String, message: String, type: String) {
        self.code = code
        self.message = message
        self.type = type
    }
}

struct ApiErrorWrapper : Decodable {

    let error: ApiError

    init(error: ApiError) {
        self.error = error
    }
}
