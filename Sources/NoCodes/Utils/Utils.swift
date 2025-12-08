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
    case sourceKey = "com.qonversion.keys.source"
    case sourceVersionKey = "com.qonversion.keys.sourceVersion"
}

extension Bundle {
    static var appVersion: String? { main.infoDictionary?[InternalConstants.appVersionBundleKey.rawValue] as? String }
}

extension UserDefaults {
    static var source: String {
        return standard.string(forKey: InternalConstants.sourceKey.rawValue) ?? "iOS"
    }
    
    static var sourceVersion: String? {
        return standard.string(forKey: InternalConstants.sourceVersionKey.rawValue)
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
