//
//  FallbackService.swift
//  Qonversion
//

import Foundation

fileprivate enum Constants: String {
    case fileName = "qonversion_ios_fallbacks"
    case fileExtension = "json"
}

/// A snapshot of project data bundled with the app. Powers products, the
/// product → permissions mapping and remote configs when the API is
/// unreachable and no cache exists yet (e.g. the very first launch without
/// a network connection).
struct FallbackData: Decodable {

    let products: [Qonversion.Product]?
    let productsPermissions: [String: [String]]?
    let remoteConfigs: [Qonversion.RemoteConfig]?

    private enum CodingKeys: String, CodingKey {
        case products
        case productsPermissions = "products_permissions"
        case remoteConfigs = "remote_config_list"
    }

    init(products: [Qonversion.Product]?, productsPermissions: [String: [String]]?, remoteConfigs: [Qonversion.RemoteConfig]? = nil) {
        self.products = products
        self.productsPermissions = productsPermissions
        self.remoteConfigs = remoteConfigs
    }

    /// Row-by-row and section-by-section, deliberately: this file is the LAST
    /// line of defense — with no network and no cache it is all the app has.
    /// A strict decode threw the whole file away over one malformed product
    /// row, taking products_permissions and remote_config_list with it. The
    /// ObjC mapper behaved the same way this does: each section was mapped on
    /// its own and unusable rows were skipped.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        products = FallbackData.lossyArray(Qonversion.Product.self, in: container, forKey: .products)
        productsPermissions = FallbackData.lossyRelations(in: container, forKey: .productsPermissions)
        remoteConfigs = FallbackData.lossyArray(Qonversion.RemoteConfig.self, in: container, forKey: .remoteConfigs)
    }

    /// An absent section stays nil (the caller tells "not shipped" from
    /// "shipped empty"); a present one yields whatever rows decoded.
    private static func lossyArray<Element: Decodable>(
        _ elementType: Element.Type,
        in container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> [Element]? {
        guard container.contains(key) else { return nil }
        guard var unkeyed: UnkeyedDecodingContainer = try? container.nestedUnkeyedContainer(forKey: key) else { return nil }

        var elements: [Element] = []
        while !unkeyed.isAtEnd {
            if let element: Element = try? unkeyed.decode(Element.self) {
                elements.append(element)
            } else {
                // Skip the malformed row; the container must still advance.
                _ = try? unkeyed.decode(AnyDecodableValue.self)
            }
        }

        return elements
    }

    private static func lossyRelations(
        in container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> [String: [String]]? {
        guard container.contains(key) else { return nil }
        guard let relations = try? container.nestedContainer(keyedBy: RelationKey.self, forKey: key) else { return nil }

        var result: [String: [String]] = [:]
        for relationKey in relations.allKeys {
            guard let entitlementIds: [String] = try? relations.decode([String].self, forKey: relationKey) else { continue }

            result[relationKey.stringValue] = entitlementIds
        }

        return result
    }

    /// The product ids in products_permissions are data, not a fixed schema.
    private struct RelationKey: CodingKey {

        let stringValue: String
        var intValue: Int? { nil }

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            return nil
        }
    }
}

protocol FallbackServiceInterface {
    func obtainFallbackData() -> FallbackData?
}

// @unchecked: the cached load is lock-guarded; the bundle never changes.
final class FallbackService: FallbackServiceInterface, @unchecked Sendable {

    private let bundle: Bundle
    private let decoder: JSONDecoder
    /// Where a file dropped at runtime is looked for, after the app bundle —
    /// injected so the location is testable.
    private let documentsDirectory: URL?

    // A successfully decoded file is immutable for the process lifetime;
    // a MISSING or broken one is not — it may appear later (the Documents
    // copy is written at runtime), so the negative outcome is never cached.
    private let lock = NSLock()
    private var cachedData: FallbackData?

    init(bundle: Bundle, decoder: JSONDecoder, documentsDirectory: URL? = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first) {
        self.bundle = bundle
        self.decoder = decoder
        self.documentsDirectory = documentsDirectory
    }

    func obtainFallbackData() -> FallbackData? {
        lock.lock()
        if let cachedData {
            lock.unlock()
            return cachedData
        }
        lock.unlock()

        guard let data: Data = fileData() else { return nil }

        guard let decoded: FallbackData = try? decoder.decode(FallbackData.self, from: data) else { return nil }

        lock.lock()
        cachedData = decoded
        lock.unlock()

        return decoded
    }

    /// The app bundle first, like production, then a copy dropped into the
    /// Documents directory at runtime.
    private func fileData() -> Data? {
        if let url: URL = bundle.url(forResource: Constants.fileName.rawValue, withExtension: Constants.fileExtension.rawValue),
           let data: Data = try? Data(contentsOf: url) {
            return data
        }

        guard let documentsDirectory else { return nil }

        let fileUrl: URL = documentsDirectory.appendingPathComponent(Constants.fileName.rawValue + "." + Constants.fileExtension.rawValue)

        return try? Data(contentsOf: fileUrl)
    }
}
