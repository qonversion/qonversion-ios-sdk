//
//  ListEnvelope.swift
//  Qonversion
//

import Foundation

/// The v4 list envelope; pagination fields are ignored until needed.
struct ListEnvelope<Element: Decodable>: Decodable {

    let data: [Element]

    init(data: [Element]) {
        self.data = data
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.container(keyedBy: CodingKeys.self).nestedUnkeyedContainer(forKey: .data)
        data = try LossyArray.decode(Element.self, from: &container)
    }

    private enum CodingKeys: String, CodingKey {
        case data
    }
}
