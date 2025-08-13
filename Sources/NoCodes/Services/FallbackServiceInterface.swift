//
//  FallbackServiceInterface.swift
//  NoCodes
//
//  Created by Suren Sarkisyan on 07.07.2025.
//  Copyright © 2025 Qonversion Inc. All rights reserved.
//

import Foundation

#if os(iOS)

protocol FallbackServiceInterface {
  func loadScreen(withContextKey contextKey: String) -> NoCodesScreen?
  func loadScreen(with id: String) -> NoCodesScreen?
} 

#endif
