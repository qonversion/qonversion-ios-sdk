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

  private enum CodingKeys: String, CodingKey {
    // After adding any keys here, duplicate them in the ResponseCodingKeys
    case id
    case body
    case context_key
    case products
  }

  private enum ResponseCodingKeys: String, CodingKey {
    // Getting screen by id works via legacy API. By context key - via the new, they have different response structure,
    // so the keys are duplicated to support both.
    case data
    case id
    case body
    case context_key
    case products
  }

  /// Internal initializer for creating a screen with modified HTML (e.g., with preloaded images).
  init(id: String, html: String, contextKey: String, products: [String] = []) {
    self.id = id
    self.html = html
    self.contextKey = contextKey
    self.products = products
  }

  public init(from decoder: Decoder) throws {
    if var arrayContainer = try? decoder.unkeyedContainer(),
       let screenContainer = try? arrayContainer.nestedContainer(keyedBy: CodingKeys.self) {
      id = try screenContainer.decode(String.self, forKey: .id)
      html = try screenContainer.decode(String.self, forKey: .body)
      contextKey = try screenContainer.decode(String.self, forKey: .context_key)
      // Older payloads and bundled fallbacks may omit `products`; default to empty.
      products = (try? screenContainer.decodeIfPresent([String].self, forKey: .products)) ?? []
    } else {
      let container = try decoder.container(keyedBy: ResponseCodingKeys.self)
      id = try container.decode(String.self, forKey: .id)
      html = try container.decode(String.self, forKey: .body)
      contextKey = try container.decode(String.self, forKey: .context_key)
      products = (try? container.decodeIfPresent([String].self, forKey: .products)) ?? []
    }
  }

  /// Creates a copy of the screen with modified HTML content.
  /// Used for replacing image URLs with base64 data URIs.
  func withHtml(_ newHtml: String) -> NoCodesScreen {
    return NoCodesScreen(id: id, html: newHtml, contextKey: contextKey, products: products)
  }
}

#endif
