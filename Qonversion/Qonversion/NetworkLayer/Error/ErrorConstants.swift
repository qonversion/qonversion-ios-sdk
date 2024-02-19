//
//  ErrorConstants.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 19.02.2024.
//

import Foundation

enum ErrorCodes: Int {
    case unauthorized = 401
    case paymentRequired = 402
    case forbidden = 403
    case internalErrorStart = 500
    case internalErrorEnd = 599
}
