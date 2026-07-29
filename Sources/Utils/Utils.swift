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

// The scan walks roughly a thousand locales and runs once per mapped transaction,
// so the answers — misses included — are memoized per currency code.
// @unchecked: the only mutable state is `symbols`, guarded by `lock` on every access.
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

        let symbol: String? = Self.resolveSymbol(for: currencyCode)

        lock.lock()
        symbols[currencyCode] = symbol
        lock.unlock()

        return symbol
    }

    /// Many locales share a currency, and most of them render it with a
    /// disambiguating prefix — ba_RU gives "RUB", ain_JP "JP¥", csw_CA "CA$".
    /// The currency's own locale is the one that needs no prefix, so the
    /// shortest symbol wins; ties keep the sorted-identifier order, which
    /// makes the answer stable across calls and launches.
    private static func resolveSymbol(for currencyCode: String) -> String? {
        var bestSymbol: String? = nil

        for identifier in sortedLocaleIdentifiers {
            let locale = Locale(identifier: identifier)
            guard locale.currencyCode == currencyCode else { continue }
            guard let symbol: String = locale.currencySymbol, !symbol.isEmpty else { continue }

            if bestSymbol == nil || symbol.count < bestSymbol!.count {
                bestSymbol = symbol
            }
        }

        return bestSymbol
    }
}

extension String {
    func toCurrencySymbol() -> String? {
        return CurrencySymbolCache.shared.symbol(for: self)
    }
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
extension Locale.Currency {
    func currencySymbol() -> String? {
        return CurrencySymbolCache.shared.symbol(for: identifier)
    }
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

/// Decodes any JSON value, carrying nothing over. Decoding it succeeds for
/// every element, which is what advances an unkeyed container past a value
/// none of the typed branches can represent.
private struct SkippedJSONValue: Decodable {
  init(from decoder: Decoder) throws {}
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
    } else if (try? container.decode(SkippedJSONValue.self)) != nil {
      // Representable in no branch above — e.g. a number larger than Double,
      // which decodeNil() also declines without moving the cursor. Skipping
      // the element is what keeps the loop advancing.
      continue
    } else {
      // The container refused to advance at all: stop with what was decoded
      // rather than spin forever.
      break
    }
  }

  return result
}

extension Error {
    var message: String {
        switch self {
        case let qonversionError as QonversionError:
            return qonversionError.message
        default:
            return localizedDescription
        }
    }
}
