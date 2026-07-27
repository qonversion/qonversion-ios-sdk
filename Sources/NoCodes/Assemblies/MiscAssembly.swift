//
//  MiscAssembly.swift
//  NoCodes
//
//  Created by Suren Sarkisyan on 18.12.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation
import OSLog

fileprivate enum IntConstants: UInt {
  case maxRequestsPerSecond = 5
}

final class MiscAssembly {
  
  let projectKey: String

  // Weak: ServicesAssembly holds MiscAssembly strongly; a strong back
  // reference would leak the whole graph on every initialize.
  weak var servicesAssembly: ServicesAssembly!
  
  init(projectKey: String) {
    self.projectKey = projectKey
  }
  
  func loggerWrapper() -> LoggerWrapper {
    let logger = Logger(subsystem: "io.qonversion.nocodes.sdk", category: "Internal")

    return LoggerWrapper(logger: logger, logLevel: .verbose)
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
    let deviceInfoCollector: DeviceInfoCollectorInterface = servicesAssembly.deviceInfoCollector()
    let headersBuilder = HeadersBuilder(projectKey: projectKey, deviceInfoCollector: deviceInfoCollector)
    
    return headersBuilder
  }
  
  func noCodesMapper() -> NoCodesMapperInterface {
    return NoCodesMapper()
  }

  func contextBuilder() -> NoCodesContextBuilderInterface {
    return NoCodesContextBuilder()
  }

  func htmlInjector() -> NoCodesHTMLInjectorInterface {
    return NoCodesHTMLInjector()
  }
}
