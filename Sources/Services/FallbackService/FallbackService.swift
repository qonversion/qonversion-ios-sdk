//
//  FallbackService.swift
//  Qonversion
//

import Foundation

fileprivate enum Constants: String {
    case fileName = "qonversion_ios_fallbacks"
    case fileExtension = "json"
}

/// A snapshot of project data bundled with the app. Powers products and the
/// product → permissions mapping when the API is unreachable and no cache
/// exists yet (e.g. the very first launch without a network connection).
struct FallbackData: Decodable {

    let products: [Qonversion.Product]?
    let productsPermissions: [String: [String]]?

    private enum CodingKeys: String, CodingKey {
        case products
        case productsPermissions = "products_permissions"
    }

    init(products: [Qonversion.Product]?, productsPermissions: [String: [String]]?) {
        self.products = products
        self.productsPermissions = productsPermissions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        products = try container.decodeIfPresent([Qonversion.Product].self, forKey: .products)
        productsPermissions = try container.decodeIfPresent([String: [String]].self, forKey: .productsPermissions)
    }
}

protocol FallbackServiceInterface {
    func obtainFallbackData() -> FallbackData?
}

final class FallbackService: FallbackServiceInterface {

    private let bundle: Bundle
    private let decoder: JSONDecoder

    init(bundle: Bundle, decoder: JSONDecoder) {
        self.bundle = bundle
        self.decoder = decoder
    }

    func obtainFallbackData() -> FallbackData? {
        guard let url = bundle.url(forResource: Constants.fileName.rawValue, withExtension: Constants.fileExtension.rawValue),
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? decoder.decode(FallbackData.self, from: data)
    }
}
