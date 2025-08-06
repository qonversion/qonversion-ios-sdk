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
  
  private let requestProcessor: RequestProcessorInterface
  private let fallbackService: FallbackServiceInterface?
  
  init(requestProcessor: RequestProcessorInterface, fallbackService: FallbackServiceInterface? = nil) {
    self.requestProcessor = requestProcessor
    self.fallbackService = fallbackService
  }
  
  func loadScreen(with id: String) async throws -> NoCodesScreen {
    do {
      let request = Request.getScreen(id: id)
      let screen: NoCodesScreen = try await requestProcessor.process(request: request, responseType: NoCodesScreen.self)
      
      return screen
    } catch {
      // Try fallback if available and error is network-related or server error
      if let fallbackService = fallbackService,
         (isNetworkError(error) || isServerError(error)) {
        if let fallbackScreen = fallbackService.loadScreen(with: id) {
          return fallbackScreen
        }
      }
      throw NoCodesError(type: .screenLoadingFailed, message: nil, error: error)
    }
  }
  
  func loadScreen(withContextKey contextKey: String) async throws -> NoCodesScreen {
    do {
      let request = Request.getScreenByContextKey(contextKey: contextKey)
      let screen: NoCodesScreen = try await requestProcessor.process(request: request, responseType: NoCodesScreen.self)
      return screen
    } catch {
      // Try fallback if available and error is network-related or server error
      if let fallbackService = fallbackService,
         (isNetworkError(error) || isServerError(error)) {
        if let fallbackScreen = fallbackService.loadScreen(withContextKey: contextKey) {
          return fallbackScreen
        }
      }
      throw NoCodesError(type: .screenLoadingFailed, message: nil, error: error)
    }
  }
  
  private func isNetworkError(_ error: Error) -> Bool {
    // Check if error is network-related (not API business logic errors)
    if let noCodesError = error as? NoCodesError {
      switch noCodesError.type {
      case .invalidRequest, .invalidResponse, .internal, .critical:
        return true
      case .screenLoadingFailed, .productsLoadingFailed, .productNotFound, .authorizationFailed, .rateLimitExceeded, .sdkInitializationError:
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
