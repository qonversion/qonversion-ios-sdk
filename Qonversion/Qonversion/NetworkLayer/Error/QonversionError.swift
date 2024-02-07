//
//  QonversionError.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 07.02.2024.
//

struct QonversionError: Error {
    let type: QonversionErrorType
    let message: String
    let error: Error?
    let additionalInfo: [String: Any]?
}
