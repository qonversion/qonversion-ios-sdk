//
//  NoCodesScreen.swift
//  NoCodes
//
//  Created by Suren Sarkisyan on 20.12.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation

#if os(iOS)

public struct NoCodesScreen: Decodable, Sendable {
  public let id: String
  let html: String
  public let contextKey: String
  /// Typed default variables of the screen configured in the builder: authored custom
  /// variables and product slots. Read them by ``NoCodesScreenVariable/key`` (may be empty).
  public let defaultVariables: [NoCodesScreenVariable]

  private enum CodingKeys: String, CodingKey {
    // After adding any keys here, duplicate them in the ResponseCodingKeys
    case id
    case body
    case context_key
    case variables
  }

  private enum ResponseCodingKeys: String, CodingKey {
    // Getting a screen by context key returns an array of screens, while getting it by id
    // returns a single object with a `data` envelope — the keys are duplicated to support
    // both response shapes.
    case data
    case id
    case body
    case context_key
    case variables
  }

  /// Internal initializer for creating a screen with modified HTML (e.g., with preloaded images).
  init(id: String, html: String, contextKey: String, defaultVariables: [NoCodesScreenVariable] = []) {
    self.id = id
    self.html = html
    self.contextKey = contextKey
    self.defaultVariables = defaultVariables
  }

  public init(from decoder: Decoder) throws {
    if var arrayContainer = try? decoder.unkeyedContainer(),
       let screenContainer = try? arrayContainer.nestedContainer(keyedBy: CodingKeys.self) {
      id = try screenContainer.decode(String.self, forKey: .id)
      html = try screenContainer.decode(String.self, forKey: .body)
      contextKey = try screenContainer.decode(String.self, forKey: .context_key)
      // Older payloads and bundled fallbacks may omit `variables`; default to empty.
      defaultVariables = (try? screenContainer.decodeIfPresent([NoCodesScreenVariable].self, forKey: .variables)) ?? []
    } else {
      let container = try decoder.container(keyedBy: ResponseCodingKeys.self)
      id = try container.decode(String.self, forKey: .id)
      html = try container.decode(String.self, forKey: .body)
      contextKey = try container.decode(String.self, forKey: .context_key)
      defaultVariables = (try? container.decodeIfPresent([NoCodesScreenVariable].self, forKey: .variables)) ?? []
    }
  }

  /// The Qonversion product id selected by default when the screen opens (the builder's
  /// Default Product), or `nil` when none is configured. Convenience over the
  /// ``NoCodesScreenVariableKind/selectedProduct`` entry of ``defaultVariables``.
  public var defaultSelectedProductId: String? {
    guard let variable = defaultVariables.first(where: { $0.kind == .selectedProduct }),
          case .string(let productId) = variable.value else {
      return nil
    }
    return productId
  }

  /// Returns the default variable configured under the given key, or `nil` when the screen
  /// has no variable with that exact (case-sensitive) key.
  ///
  /// Keys are only unique within a kind — a custom variable and a product slot may share a
  /// name — so pass `kind` to disambiguate; without it the first match in payload order
  /// (custom variables, then product slots, then the selected product) is returned.
  ///
  /// For the default selected product prefer ``defaultSelectedProductId`` — it needs no key.
  public func defaultVariable(forKey key: String, kind: NoCodesScreenVariableKind? = nil) -> NoCodesScreenVariable? {
    return defaultVariables.first { $0.key == key && (kind == nil || $0.kind == kind) }
  }

  /// Creates a copy of the screen with modified HTML content.
  /// Used for replacing image URLs with base64 data URIs.
  func withHtml(_ newHtml: String) -> NoCodesScreen {
    return NoCodesScreen(id: id, html: newHtml, contextKey: contextKey, defaultVariables: defaultVariables)
  }
}

/// A typed default variable of a No-Codes screen, configured in the builder and delivered
/// to the SDK at screen load so it can be read by key. The value keeps its authored type
/// (bool / string / number) rather than being coerced to a string.
public struct NoCodesScreenVariable: Decodable, Sendable {
  /// What the variable represents — see ``NoCodesScreenVariableKind``.
  public let kind: NoCodesScreenVariableKind
  /// Variable name it is addressed by (`variable.<key>` in the builder for custom
  /// variables, the slot name for product slots). May contain spaces.
  public let key: String
  /// Authored value type: `"boolean"`, `"string"` or `"number"`.
  public let type: String
  /// The configured default value, preserving its native type.
  public let value: NoCodesScreenVariableValue

  private enum CodingKeys: String, CodingKey {
    case kind
    case key
    case type
    case value
  }

  init(kind: NoCodesScreenVariableKind, key: String, type: String, value: NoCodesScreenVariableValue) {
    self.kind = kind
    self.key = key
    self.type = type
    self.value = value
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    // Payloads predating the `kind` field carry only authored custom variables; unknown
    // kinds (added on the backend after this SDK version) must not fail the decode.
    if let rawKind = try container.decodeIfPresent(String.self, forKey: .kind) {
      kind = NoCodesScreenVariableKind(rawValue: rawKind) ?? .unknown
    } else {
      kind = .custom
    }
    key = try container.decode(String.self, forKey: .key)
    type = try container.decode(String.self, forKey: .type)
    value = try container.decodeIfPresent(NoCodesScreenVariableValue.self, forKey: .value) ?? .none
  }
}

/// Kind of a ``NoCodesScreenVariable`` — what it was configured as in the builder.
/// The set may grow in future backend versions; values this SDK version does not know
/// decode as ``unknown`` instead of failing.
public enum NoCodesScreenVariableKind: String, Sendable {
  /// A Screen Variable authored in the builder's Variables section.
  case custom
  /// A product slot: ``NoCodesScreenVariable/key`` is the slot name and
  /// ``NoCodesScreenVariable/value`` is the default Qonversion product id assigned to it.
  case product
  /// The screen's Default Product configured in the builder:
  /// ``NoCodesScreenVariable/key`` is always `"default_selected_product"` and
  /// ``NoCodesScreenVariable/value`` is the Qonversion product id selected by default.
  case selectedProduct = "selected_product"
  /// A kind introduced on the backend after this SDK version was released.
  case unknown
}

/// Typed value of a ``NoCodesScreenVariable``. Preserves the authored JSON type instead of
/// collapsing everything to `String`.
public enum NoCodesScreenVariableValue: Decodable, Equatable, Sendable {
  case bool(Bool)
  case string(String)
  case number(Double)
  /// A `null`/absent authored default.
  case none

  /// The value rendered as a plain string regardless of its native type: `"true"`/`"false"`
  /// for booleans, the string itself, a number without a trailing `.0` when integral
  /// (`34`, `3.5`), or an empty string for ``none``.
  public var stringValue: String {
    switch self {
    case .bool(let boolValue):
      return boolValue ? "true" : "false"
    case .string(let stringValue):
      return stringValue
    case .number(let numberValue):
      if numberValue.truncatingRemainder(dividingBy: 1) == 0, abs(numberValue) < 1e15 {
        return String(Int64(numberValue))
      }
      return String(numberValue)
    case .none:
      return ""
    }
  }

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
