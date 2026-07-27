//
//  FallbackService.swift
//  NoCodes
//
//  Created by Suren Sarkisyan on 07.07.2025.
//  Copyright © 2025 Qonversion Inc. All rights reserved.
//

import Foundation

// MARK: - Fallback File Structures

struct FallbackFile: Decodable, Sendable {
  let screens: [String: NoCodesScreen]
}

// @unchecked: the only mutable state is `cachedFallbackFile`, guarded by
// `cacheLock` on every access.
final class FallbackService: FallbackServiceInterface, @unchecked Sendable {
  private let logger: LoggerWrapper
  private let bundle: Bundle
  private let fallbackFileName: String
  private let decoder: JSONDecoder
  
  // Lazy caching. Screens are loaded from concurrent screen requests, so the
  // cache is guarded; the lock is only held around synchronous work.
  private let cacheLock = NSLock()
  private var cachedFallbackFile: FallbackFile?

  init(logger: LoggerWrapper, bundle: Bundle = .main, fallbackFileName: String = "nocodes_fallbacks.json", decoder: JSONDecoder = JSONDecoder()) {
    self.logger = logger
    self.bundle = bundle
    self.fallbackFileName = fallbackFileName
    self.decoder = decoder
  }
  
  func loadScreen(withContextKey contextKey: String) -> NoCodesScreen? {
    do {
      let fallbackFile = try loadFallbackData()
      
      guard let screen = fallbackFile.screens[contextKey] else {
        logger.debug("No fallback screen found for context key: \(contextKey)")
        return nil
      }
      
      logger.debug("Successfully loaded fallback screen for context key: \(contextKey)")
      return screen
      
    } catch {
      logger.error("Failed to load fallback screen: \(error.localizedDescription)")
      return nil
    }
  }
  
  func loadScreen(with id: String) -> NoCodesScreen? {
    do {
      let fallbackFile = try loadFallbackData()
      
      // Search for screen with matching ID among all screens
      let matchingScreen = fallbackFile.screens.values.first { $0.id == id }
      
      guard let screen = matchingScreen else {
        logger.debug("No fallback screen found for id: \(id)")
        return nil
      }
      
      logger.debug("Successfully loaded fallback screen for id: \(id)")
      return screen
      
    } catch {
      logger.error("Failed to load fallback screen: \(error.localizedDescription)")
      return nil
    }
  }
  
  
  
  private func loadFallbackData() throws -> FallbackFile {
    // Return cached data if already loaded
    let cached: FallbackFile? = cachedFile()
    if let cached {
      return cached
    }

    // Load from file if not cached
    guard let path = FallbackService.fallbackFilePath(for: fallbackFileName, in: bundle) else {
      logger.debug("Fallback file not found: \(fallbackFileName)")
      throw FallbackError.fileNotFound
    }
    
    let url = URL(fileURLWithPath: path)
    let data = try Data(contentsOf: url)
    
    let fallbackFile = try decoder.decode(FallbackFile.self, from: data)
    
    // Cache the loaded data
    store(fallbackFile: fallbackFile)

    logger.debug("Fallback file loaded and cached: \(fallbackFileName)")
    return fallbackFile
  }

  private func cachedFile() -> FallbackFile? {
    cacheLock.lock()
    defer { cacheLock.unlock() }

    return cachedFallbackFile
  }

  private func store(fallbackFile: FallbackFile) {
    cacheLock.lock()
    defer { cacheLock.unlock() }

    cachedFallbackFile = fallbackFile
  }

  static func isFallbackFileAvailable(_ fileName: String = "nocodes_fallbacks.json", in bundle: Bundle = .main) -> Bool {
    return fallbackFilePath(for: fileName, in: bundle) != nil
  }

  private static func fallbackFilePath(for fileName: String, in bundle: Bundle) -> String? {
    let resource: String = fileName.replacingOccurrences(of: ".json", with: "")

    return bundle.path(forResource: resource, ofType: "json")
  }
}

// MARK: - Errors

enum FallbackError: Error {
  case fileNotFound
  case invalidScreenData
}
