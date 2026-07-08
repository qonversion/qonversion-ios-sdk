//
//  ListEnvelope.swift
//  Qonversion
//

import Foundation

/// The v4 list envelope; pagination fields are ignored until needed.
struct ListEnvelope<Element: Decodable>: Decodable {
    let data: [Element]
}
