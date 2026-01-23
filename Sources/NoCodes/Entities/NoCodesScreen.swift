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
  
  private enum CodingKeys: String, CodingKey {
    // After adding any keys here, duplicate them in the ResponseCodingKeys
    case id
    case body
    case context_key
  }
  
  private enum ResponseCodingKeys: String, CodingKey {
    // Getting screen by id works via legacy API. By context key - via the new, they have different response structure,
    // so the keys are duplicated to support both.
    case data
    case id
    case body
    case context_key
  }
  
  /// Internal initializer for creating a screen with modified HTML (e.g., with preloaded images).
  init(id: String, html: String, contextKey: String) {
    self.id = id
    self.html = html
    self.contextKey = contextKey
  }
  
  public init(from decoder: Decoder) throws {
    if var arrayContainer = try? decoder.unkeyedContainer(),
       let screenContainer = try? arrayContainer.nestedContainer(keyedBy: CodingKeys.self) {
      id = try screenContainer.decode(String.self, forKey: .id)
      html = try screenContainer.decode(String.self, forKey: .body)
      contextKey = try screenContainer.decode(String.self, forKey: .context_key)
    } else {
      let container = try decoder.container(keyedBy: ResponseCodingKeys.self)
      id = try container.decode(String.self, forKey: .id)
      html = try container.decode(String.self, forKey: .body)
      contextKey = try container.decode(String.self, forKey: .context_key)
    }
  }
  
  /// Creates a copy of the screen with modified HTML content.
  /// Used for replacing image URLs with base64 data URIs.
  func withHtml(_ newHtml: String) -> NoCodesScreen {
    return NoCodesScreen(id: id, html: newHtml, contextKey: contextKey)
  }
}

#endif 