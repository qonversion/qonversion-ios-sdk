//
//  ServicesAssembly.swift
//  NoCodes
//
//  Created by Suren Sarkisyan on 18.12.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation

#if os(iOS)

fileprivate enum StringConstants: String {
  case baseURL = "https://api2.qonversion.io/"
}

fileprivate enum ServicesConstants {
  static let defaultTimeout: TimeInterval = 20.0
}

fileprivate enum FallbackConstants {
  static let defaultFileName = "nocodes_fallbacks.json"
  static let fallbackTimeout: TimeInterval = 5.0
}

final class ServicesAssembly {
  
  private let miscAssembly: MiscAssembly
  private var deviceInfoCollectorInstance: DeviceInfoCollector?
  private let fallbackFileName: String?
  
  init(miscAssembly: MiscAssembly, fallbackFileName: String? = nil) {
    self.miscAssembly = miscAssembly
    self.fallbackFileName = fallbackFileName
  }
  
  func noCodesService() -> NoCodesServiceInterface {
    return NoCodesService(requestProcessor: requestProcessor(), fallbackService: fallbackService())
  }
  
  func fallbackService() -> FallbackServiceInterface? {
    return FallbackService(
      logger: miscAssembly.loggerWrapper(),
      fallbackFileName: getFallbackFileName(),
      decoder: miscAssembly.jsonDecoder(),
      encoder: miscAssembly.encoder()
    )
  }
  
  func requestProcessor() -> RequestProcessorInterface {
    let networkProvider: NetworkProviderInterface = networkProvider()
    let headersBuilder: HeadersBuilderInterface = miscAssembly.headersBuilder()
    let errorHandler: NetworkErrorHandlerInterface = miscAssembly.errorHandler()
    let decoder: ResponseDecoderInterface = miscAssembly.responseDecoder()
    let rateLimiter: RateLimiterInterface = miscAssembly.rateLimiter()
    
    let retriableRequestsList: [Request] = []
    
    let processor = RequestProcessor(baseURL: StringConstants.baseURL.rawValue, networkProvider: networkProvider, headersBuilder: headersBuilder, errorHandler: errorHandler, decoder: decoder, retriableRequestsList: retriableRequestsList, rateLimiter: rateLimiter)
    
    return processor
  }
  
  func networkProvider() -> NetworkProviderInterface {
    let fallbackAvailable = FallbackService.isFallbackFileAvailable(getFallbackFileName())
    let timeout: TimeInterval? = fallbackAvailable ? FallbackConstants.fallbackTimeout : ServicesConstants.defaultTimeout
    
    let networkProvider = NetworkProvider(timeout: timeout)
    return networkProvider
  }
  
  func urlSession() -> URLSession {
    return URLSession.shared
  }
  
  func deviceInfoCollector() -> DeviceInfoCollectorInterface {
    if let deviceInfoCollectorInstance {
      return deviceInfoCollectorInstance
    }
    
    let deviceInfoCollector = DeviceInfoCollector()
    deviceInfoCollectorInstance = deviceInfoCollector
    
    return deviceInfoCollector
  }
  
  // MARK: - Private Methods
  
  private func getFallbackFileName() -> String {
    return fallbackFileName ?? FallbackConstants.defaultFileName
  }
  
}

#endif
