//
//  ErrorConstants.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 19.02.2024.
//

import Foundation

enum ErrorConstants: String {
    case messageKey = "message"
}

enum ResponseCode: Int {
    case successMin = 200
    case noContent = 204
    case successMax = 299
    case unauthorized = 401
    case paymentRequired = 402
    case forbidden = 403
    case internalErrorMin = 500
    case internalErrorMax = 599
}
