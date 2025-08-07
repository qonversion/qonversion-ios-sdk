//
//  NoCodesServiceInterface.swift
//  NoCodes
//
//  Created by Suren Sarkisyan on 18.12.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation

#if os(iOS)

protocol NoCodesServiceInterface {
  
  func loadScreen(with id: String) async throws -> NoCodesScreen
  
  func loadScreen(withContextKey contextKey: String) async throws -> NoCodesScreen
  
}

#endif
