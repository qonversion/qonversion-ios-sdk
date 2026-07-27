//
//  EmptyApiResponse.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 11.04.2024.
//

import Foundation

class EmptyApiResponse: Decodable {

    enum CodingKeys: CodingKey {}

    init() {}

    required public init(from decoder: any Decoder) throws {}
}
