//
//  NoCodesService.swift
//  NoCodes
//
//  Created by Suren Sarkisyan on 18.12.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation

#if os(iOS)

class NoCodesService: NoCodesServiceInterface {
  
  private static let cacheQueueLabel = "io.qonversion.nocodes.cache"
  
  private let requestProcessor: RequestProcessorInterface
  private let fallbackService: FallbackServiceInterface?
  private let imagePreloader: ImagePreloaderInterface?
  
  // Local screen cache
  private var screensById: [String: NoCodesScreen] = [:]
  private var screensByContextKey: [String: NoCodesScreen] = [:]
  private let cacheQueue = DispatchQueue(label: cacheQueueLabel, attributes: .concurrent)
  
  init(
    requestProcessor: RequestProcessorInterface,
    fallbackService: FallbackServiceInterface? = nil,
    imagePreloader: ImagePreloaderInterface? = nil
  ) {
    self.requestProcessor = requestProcessor
    self.fallbackService = fallbackService
    self.imagePreloader = imagePreloader
  }
  
  func loadScreen(with id: String) async throws -> NoCodesScreen {
    // First check cache (already has preloaded images if preloaded)
    if let cachedScreen = getCachedScreen(id: id) {
      return cachedScreen
    }
    
    do {
      let request = Request.getScreen(id: id)
      let screen: NoCodesScreen = try await requestProcessor.process(request: request, responseType: NoCodesScreen.self)
      
      // Save to cache (no image preloading for on-demand loads)
      cacheScreen(screen)
      
      return screen
    } catch {
      // Try fallback if available and error is network-related or server error
      if let fallbackService = fallbackService,
         (isNetworkError(error) || isServerError(error)) {
        if let fallbackScreen = fallbackService.loadScreen(with: id) {
          // Return fallback directly (no image preloading for fallback)
          return fallbackScreen
        }
      }
      throw NoCodesError(type: .screenLoadingFailed, message: nil, error: error)
    }
  }
  
  func loadScreen(withContextKey contextKey: String) async throws -> NoCodesScreen {
    // First check cache (already has preloaded images if preloaded)
    if let cachedScreen = getCachedScreen(contextKey: contextKey) {
      return cachedScreen
    }
    
    do {
      let request = Request.getScreenByContextKey(contextKey: contextKey)
      let screens: [NoCodesScreen] = try await requestProcessor.process(request: request, responseType: [NoCodesScreen].self)
      
      guard let screen = screens.first else {
        throw NoCodesError(type: .screenNotFound)
      }

      // Save to cache (no image preloading for on-demand loads)
      cacheScreen(screen)
      
      return screen
    } catch {
      // Try fallback if available and error is network-related or server error
      if let fallbackService = fallbackService,
         (isNetworkError(error) || isServerError(error)) {
        if let fallbackScreen = fallbackService.loadScreen(withContextKey: contextKey) {
          // Return fallback directly (no image preloading for fallback)
          return fallbackScreen
        }
      }
      throw NoCodesError(type: .screenLoadingFailed, message: nil, error: error)
    }
  }
  
  func preloadScreens() async throws -> [NoCodesScreen] {
    let request = Request.getPreloadScreens()
    let screens: [NoCodesScreen] = try await requestProcessor.process(request: request, responseType: [NoCodesScreen].self)
    
    // Preload images and replace URLs with base64 data URIs
    let processedScreens = await preloadImagesForScreens(screens)
    
    // Cache preloaded screens with embedded images
    cacheScreens(processedScreens)
    
    return processedScreens
  }
  
  // MARK: - Image Preloading
  
  /// Preloads images for multiple screens concurrently.
  /// Only used during preloadScreens() - on-demand loads skip image preloading.
  private func preloadImagesForScreens(_ screens: [NoCodesScreen]) async -> [NoCodesScreen] {
    guard let imagePreloader = imagePreloader else {
      return screens
    }
    
    return await withTaskGroup(of: (Int, NoCodesScreen).self) { group in
      for (index, screen) in screens.enumerated() {
        group.addTask {
          let processedHtml = await imagePreloader.preloadImages(in: screen.html)
          let processedScreen = screen.withHtml(processedHtml)
          return (index, processedScreen)
        }
      }
      
      var results = [(Int, NoCodesScreen)]()
      for await result in group {
        results.append(result)
      }
      
      // Sort by original index to maintain order
      return results.sorted { $0.0 < $1.0 }.map { $0.1 }
    }
  }
  
  // MARK: - Private Cache Methods
  
  private func getCachedScreen(id: String) -> NoCodesScreen? {
    return cacheQueue.sync {
      return screensById[id]
    }
  }
  
  private func getCachedScreen(contextKey: String) -> NoCodesScreen? {
    return cacheQueue.sync {
      return screensByContextKey[contextKey]
    }
  }
  
  private func cacheScreen(_ screen: NoCodesScreen) {
    cacheQueue.async(flags: .barrier) {
      self.screensById[screen.id] = screen
      self.screensByContextKey[screen.contextKey] = screen
    }
  }
  
  private func cacheScreens(_ screens: [NoCodesScreen]) {
    cacheQueue.async(flags: .barrier) {
      screens.forEach { screen in
        self.screensById[screen.id] = screen
        self.screensByContextKey[screen.contextKey] = screen
      }
    }
  }
  
  private func isNetworkError(_ error: Error) -> Bool {
    // Check if error is network-related (not API business logic errors)
    if let noCodesError = error as? NoCodesError {
      switch noCodesError.type {
      case .invalidRequest, .invalidResponse, .internal, .critical:
        return true
      case .screenLoadingFailed, .screenNotFound, .productsLoadingFailed, .productNotFound, .authorizationFailed, .rateLimitExceeded, .sdkInitializationError, .clientError:
        return false
      case .unknown:
        return true
      }
    }
    
    // Check for common network errors
    let nsError = error as NSError
    return nsError.domain == NSURLErrorDomain ||
    nsError.domain == "com.apple.dt.XCTestErrorDomain" ||
    error.localizedDescription.contains("network") ||
    error.localizedDescription.contains("connection") ||
    error.localizedDescription.contains("timeout")
  }
  
  private func isServerError(_ error: Error) -> Bool {
    let nsError = error as NSError
    let code = nsError.code
    
    // HTTP errors
    if let response = nsError.userInfo["response"] as? HTTPURLResponse {
      let statusCode = response.statusCode
      // Server errors (500-599)
      if (500...599).contains(statusCode) { return true }
      // Rate limiting
      if statusCode == 429 { return true }
      // Geoblocking/Censorship/Sanctions
      if statusCode == 403 || statusCode == 451 { return true }
    }
    
    // DNS errors
    if code == NSURLErrorCannotFindHost ||
        code == NSURLErrorDNSLookupFailed { return true }
    
    // Provider-level blocking/geoblocking
    if code == NSURLErrorCannotConnectToHost ||
        code == NSURLErrorNetworkConnectionLost ||
        code == NSURLErrorNotConnectedToInternet { return true }
    
    // CDN/load balancer issues
    if code == NSURLErrorTimedOut ||
        code == NSURLErrorCannotFindHost { return true }
    
    // Check error description for keywords
    let description = error.localizedDescription.lowercased()
    let blockedKeywords = ["blocked", "forbidden", "unavailable", "restricted", "geoblocked", "censored", "sanctioned"]
    if blockedKeywords.contains(where: { description.contains($0) }) { return true }
    
    // Check for status codes in description
    let statusCodes = ["403", "451", "429", "503", "500", "502", "504"]
    if statusCodes.contains(where: { description.contains($0) }) { return true }
    
    return false
  }
  
}

#endif
