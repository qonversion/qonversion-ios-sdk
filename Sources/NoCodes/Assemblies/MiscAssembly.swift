//
//  MiscAssembly.swift
//  NoCodes
//
//  Created by Suren Sarkisyan on 18.12.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation
import OSLog
import StoreKit

#if os(iOS)

fileprivate enum SDKLevelConstants: String {
  case version = "0.1.3"
}

fileprivate enum IntConstants: UInt {
  case maxRequestsPerSecond = 5
}

final class MiscAssembly {
  
  let projectKey: String
  var servicesAssembly: ServicesAssembly!
  
  init(projectKey: String) {
    self.projectKey = projectKey
  }
  
  func encoder() -> JSONEncoder {
    return JSONEncoder()
  }
  
  func loggerWrapper() -> LoggerWrapper {
    if #available(iOS 14.0, *) {
      let logger = Logger(subsystem: "io.qonversion.nocodes.sdk", category: "Internal")
      
      return LoggerWrapper(logger: logger, logLevel: .verbose)
    } else {
      return LoggerWrapper()
    }
  }
  
  func rateLimiter() -> RateLimiterInterface {
    let rateLimiter = RateLimiter(maxRequestsPerSecond: IntConstants.maxRequestsPerSecond.rawValue)
    
    return rateLimiter
  }
  
  func jsonDecoder() -> JSONDecoder {
    let jsonDecoder = JSONDecoder()
    jsonDecoder.dateDecodingStrategy = .secondsSince1970
    
    return jsonDecoder
  }
  
  func responseDecoder() -> ResponseDecoderInterface {
    let jsonDecoder = jsonDecoder()
    
    let responseDecoder = ResponseDecoder(decoder: jsonDecoder)
    
    return responseDecoder
  }
  
  func errorHandler() -> NetworkErrorHandlerInterface {
    let criticalErrorCodes: [ResponseCode] = [
      ResponseCode.unauthorized,
      ResponseCode.paymentRequired,
      ResponseCode.forbidden
    ]
    
    let responseDecoder: ResponseDecoderInterface = responseDecoder()
    
    let networkErrorHandler = NetworkErrorHandler(criticalErrorCodes: criticalErrorCodes, decoder: responseDecoder)
    
    return networkErrorHandler
  }
  
  func headersBuilder() -> HeadersBuilderInterface {
    let deviceInfoCollector = servicesAssembly.deviceInfoCollector()
    let headersBuilder = HeadersBuilder(projectKey: projectKey, sdkVersion: SDKLevelConstants.version.rawValue, deviceInfoCollector: deviceInfoCollector)
    
    return headersBuilder
  }
  
  func noCodesMapper() -> NoCodesMapperInterface {
    return NoCodesMapper()
  }
}

#endif
