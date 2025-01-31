//
//  Screen.swift
//  NoCodes
//
//  Created by Suren Sarkisyan on 20.12.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation

extension NoCodes {
  
  struct Screen: Decodable {
    let id: String
    let html: String
    
    private enum CodingKeys: String, CodingKey {
      case id
      case body
    }
    
    private enum ResponseCodingKeys: String, CodingKey {
      case data
    }
    
    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: ResponseCodingKeys.self)
      let screenContainer = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: ResponseCodingKeys.data)
      
      id = try screenContainer.decode(String.self, forKey: .id)
      html = try screenContainer.decode(String.self, forKey: .body)
    }
  }
  
}
