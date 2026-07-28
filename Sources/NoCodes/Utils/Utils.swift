//
//  Utils.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 15.02.2024.
//

import Foundation
import StoreKit

typealias Codable = Decodable & Encodable

enum InternalConstants: String {
    case storagePrefix = "io.qonversion.sdk.storage."
    case appVersionBundleKey = "CFBundleShortVersionString"
}

extension Bundle {
    static var appVersion: String? { main.infoDictionary?[InternalConstants.appVersionBundleKey.rawValue] as? String }
}

// Locale.availableIdentifiers has no stable order — scan a sorted copy so
// the resolved currency symbol is deterministic across calls and launches.
fileprivate let sortedLocaleIdentifiers: [String] = Locale.availableIdentifiers.sorted()

/// The scan walks roughly a thousand locales, and a paywall resolves the symbol
/// once per product on the main actor, so the answers are memoized.
// @unchecked: the only mutable state is `symbols`, guarded by `lock` on every
// access.
private final class CurrencySymbolCache: @unchecked Sendable {

    static let shared = CurrencySymbolCache()

    private let lock = NSLock()
    private var symbols: [String: String?] = [:]

    func symbol(for currencyCode: String) -> String? {
        lock.lock()
        let cached: String?? = symbols[currencyCode]
        lock.unlock()

        if let cached {
            return cached
        }

        let locale: Locale? = sortedLocaleIdentifiers.lazy.map { Locale(identifier: $0) }.first { $0.currencyCode == currencyCode }
        let symbol: String? = locale?.currencySymbol

        lock.lock()
        symbols[currencyCode] = symbol
        lock.unlock()

        return symbol
    }
}

extension String {
    func toCurrencySymbol() -> String? {
        return CurrencySymbolCache.shared.symbol(for: self)
    }
}

extension CharacterSet {
    /// `.urlPathAllowed` still permits `/`, `?` and `#`, so a caller-supplied
    /// value escaped with it could break out of its own path segment.
    static let urlPathComponentAllowed: CharacterSet = {
        var allowed: CharacterSet = .urlPathAllowed
        allowed.remove(charactersIn: "/?#")

        return allowed
    }()
}

// The below decoding implementations are taken from https://adamrackis.dev/blog/swift-codable-any
struct JSONCodingKeys: CodingKey {
  var stringValue: String

  init(stringValue: String) {
    self.stringValue = stringValue
  }

  var intValue: Int?

  init?(intValue: Int) {
    self.init(stringValue: "\(intValue)")
    self.intValue = intValue
  }
}

func decode(fromObject container: KeyedDecodingContainer<JSONCodingKeys>) -> [String: Any] {
  var result: [String: Any] = [:]

  for key in container.allKeys {
    if let val = try? container.decode(Int.self, forKey: key) {
      result[key.stringValue] = val
    } else if let val = try? container.decode(Double.self, forKey: key) {
      result[key.stringValue] = val
    } else if let val = try? container.decode(String.self, forKey: key) {
      result[key.stringValue] = val
    } else if let val = try? container.decode(Bool.self, forKey: key) {
      result[key.stringValue] = val
    } else if let nestedContainer = try? container.nestedContainer(
      keyedBy: JSONCodingKeys.self, forKey: key)
    {
      result[key.stringValue] = decode(fromObject: nestedContainer)
    } else if var nestedArray = try? container.nestedUnkeyedContainer(forKey: key) {
      result[key.stringValue] = decode(fromArray: &nestedArray)
    } else if (try? container.decodeNil(forKey: key)) == true {
      result.updateValue(Any?(nil) as Any, forKey: key.stringValue)
    }
  }

  return result
}

func decode(fromArray container: inout UnkeyedDecodingContainer) -> [Any] {
  var result: [Any] = []

  while !container.isAtEnd {
    if let value = try? container.decode(String.self) {
      result.append(value)
    } else if let value = try? container.decode(Int.self) {
      result.append(value)
    } else if let value = try? container.decode(Double.self) {
      result.append(value)
    } else if let value = try? container.decode(Bool.self) {
      result.append(value)
    } else if let nestedContainer = try? container.nestedContainer(keyedBy: JSONCodingKeys.self) {
      result.append(decode(fromObject: nestedContainer))
    } else if var nestedArray = try? container.nestedUnkeyedContainer() {
      result.append(decode(fromArray: &nestedArray))
    } else if (try? container.decodeNil()) == true {
      result.append(Any?(nil) as Any)
    }
  }

  return result
}
