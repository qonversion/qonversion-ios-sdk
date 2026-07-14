//
//  NoCodesScreen.swift
//  NoCodes
//
//  Created by Suren Sarkisyan on 20.12.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation

#if os(iOS)

public struct NoCodesScreen: Decodable {
  let id: String
  let html: String
  let contextKey: String
  /// Qonversion product ids configured in the builder for this screen (may be empty).
  let products: [String]
  /// Screen variables authored in the builder for this screen, read by key (may be empty).
  let variables: [NoCodesScreenVariable]

  private enum CodingKeys: String, CodingKey {
    // After adding any keys here, duplicate them in the ResponseCodingKeys
    case id
    case body
    case context_key
    case products
    case variables
  }

  private enum ResponseCodingKeys: String, CodingKey {
    // Getting screen by id works via legacy API. By context key - via the new, they have different response structure,
    // so the keys are duplicated to support both.
    case data
    case id
    case body
    case context_key
    case products
    case variables
  }

  /// Internal initializer for creating a screen with modified HTML (e.g., with preloaded images).
  init(id: String, html: String, contextKey: String, products: [String] = [], variables: [NoCodesScreenVariable] = []) {
    self.id = id
    self.html = html
    self.contextKey = contextKey
    self.products = products
    self.variables = variables
  }

  public init(from decoder: Decoder) throws {
    if var arrayContainer = try? decoder.unkeyedContainer(),
       let screenContainer = try? arrayContainer.nestedContainer(keyedBy: CodingKeys.self) {
      id = try screenContainer.decode(String.self, forKey: .id)
      html = try screenContainer.decode(String.self, forKey: .body)
      contextKey = try screenContainer.decode(String.self, forKey: .context_key)
      // Older payloads and bundled fallbacks may omit `products`; default to empty.
      products = (try? screenContainer.decodeIfPresent([String].self, forKey: .products)) ?? []
      variables = (try? screenContainer.decodeIfPresent([NoCodesScreenVariable].self, forKey: .variables)) ?? []
    } else {
      let container = try decoder.container(keyedBy: ResponseCodingKeys.self)
      id = try container.decode(String.self, forKey: .id)
      html = try container.decode(String.self, forKey: .body)
      contextKey = try container.decode(String.self, forKey: .context_key)
      products = (try? container.decodeIfPresent([String].self, forKey: .products)) ?? []
      variables = (try? container.decodeIfPresent([NoCodesScreenVariable].self, forKey: .variables)) ?? []
    }
  }

  /// Creates a copy of the screen with modified HTML content.
  /// Used for replacing image URLs with base64 data URIs.
  func withHtml(_ newHtml: String) -> NoCodesScreen {
    return NoCodesScreen(id: id, html: newHtml, contextKey: contextKey, products: products, variables: variables)
  }
}

/// A No-Codes screen variable authored in the builder, delivered to the SDK at screen load
/// so it can be read by key. The value keeps its authored type (bool / string / number) rather
/// than being coerced to a string.
public struct NoCodesScreenVariable: Decodable {
  /// Variable name it is addressed by (`variable.<key>` in the builder). May contain spaces.
  public let key: String
  /// Authored type: `"boolean"`, `"string"` or `"number"`.
  public let type: String
  /// The authored default value, preserving its native type.
  public let value: NoCodesScreenVariableValue

  private enum CodingKeys: String, CodingKey {
    case key
    case type
    case value
  }
}

/// Typed value of a ``NoCodesScreenVariable``. Preserves the authored JSON type instead of
/// collapsing everything to `String`.
public enum NoCodesScreenVariableValue: Decodable, Equatable {
  case bool(Bool)
  case string(String)
  case number(Double)
  /// A `null`/absent authored default.
  case none

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .none
      return
    }
    // Order matters: a JSON boolean must be tried before Double, otherwise `true`/`false`
    // could be misread. JSONDecoder keeps booleans and numbers distinct, so this is safe.
    if let boolValue = try? container.decode(Bool.self) {
      self = .bool(boolValue)
    } else if let numberValue = try? container.decode(Double.self) {
      self = .number(numberValue)
    } else if let stringValue = try? container.decode(String.self) {
      self = .string(stringValue)
    } else {
      self = .none
    }
  }
}

#endif
