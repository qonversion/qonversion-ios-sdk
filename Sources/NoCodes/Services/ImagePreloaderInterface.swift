//
//  ImagePreloaderInterface.swift
//  NoCodes
//
//  Created on 22.01.2026.
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

import Foundation

#if os(iOS)

/// Protocol for preloading images in HTML content and converting them to base64 data URIs.
protocol ImagePreloaderInterface {
  
  /// Processes HTML content by extracting image URLs, downloading images,
  /// and replacing URLs with base64 data URIs.
  /// - Parameter html: The original HTML content containing image URLs.
  /// - Returns: Modified HTML with image URLs replaced by base64 data URIs.
  func preloadImages(in html: String) async -> String
  
}

#endif
