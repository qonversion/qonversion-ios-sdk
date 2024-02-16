//
//  RateLimiter.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 08.02.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//
import Foundation

enum RateLimitedRequestType: Int {
  case initRequest
  case remoteConfig
  case attachUserToExperiment
  case detachUserFromExperiment
  case purchase
  case userInfo
  case attribution
  case getProperties
  case eligibilityForProducts
  case identify
  case attachUserToRemoteConfiguration
  case detachUserFromRemoteConfiguration
}

final class RateLimiter {
  private var maxRequestsPerSecond: UInt
  private var requests: [RateLimitedRequestType: [LimitedRequest]] = [:]
  
  init(maxRequestsPerSecond: UInt) {
    self.maxRequestsPerSecond = maxRequestsPerSecond
  }
  
  func validateRateLimit(requestType: RateLimitedRequestType, params: RequestBody) -> QonversionError? {
    let hash: Int = calculateHashForDictionary(dict: params)
    return validateRateLimit(requestType: requestType, hash: hash)
  }

  func validateRateLimit(requestType: RateLimitedRequestType, hash: Int) -> QonversionError? {
    if isRateLimitExceeded(requestType: requestType, hash: hash) {
      let error = QonversionError(type: .rateLimitExceeded, message: "Rate limit exceeded for the current request", error: nil, additionalInfo: nil)
      return error
    } else {
      saveRequest(requestType: requestType, hash: hash)
      return nil
    }
  }
  
  func saveRequest(requestType: RateLimitedRequestType, hash: Int) {
    let timestamp: TimeInterval = Date().timeIntervalSince1970
    
    if requests[requestType] == nil {
      requests[requestType] = []
    }
    
    let request = LimitedRequest(timestamp: timestamp, hash: hash)
    requests[requestType]?.append(request)
  }
  
  func isRateLimitExceeded(requestType: RateLimitedRequestType, hash: Int) -> Bool {
    removeOutdatedRequests(requestType: requestType)
    
    guard let requestsPerType = requests[requestType] else {
      return false
    }
    
    var matchCount = 0
    for request in requestsPerType where matchCount < maxRequestsPerSecond {
      if request.hash == hash {
        matchCount += 1
      }
    }
    
    return matchCount >= maxRequestsPerSecond
  }
  
  // MARK: Private
  
  private func removeOutdatedRequests(requestType: RateLimitedRequestType) {
    guard let requestsPerType: [LimitedRequest] = requests[requestType] else {
      return
    }
    
    let timestamp: TimeInterval = Date().timeIntervalSince1970
    var filteredRequests: [LimitedRequest] = []
    for request in requestsPerType.reversed() {
      let ts: TimeInterval = request.timestamp
      if timestamp - ts < 1 /* sec */ {
        filteredRequests.insert(request, at: 0)
      } else {
        break
      }
    }
    
    requests[requestType] = filteredRequests
  }
  
  private func calculateHashForDictionary(dict: [String: AnyHashable]) -> Int {
    var result: Int = 1
    let prime: Int = 31
    
    for (key, value) in dict {
      let keyHash: Int = key.hashValue
      let valueHash: Int = calculateHashForValue(value: value)
      
      result = prime &* result &+ Int(keyHash)
      result = prime &* result &+ valueHash
    }
    
    return result
  }
  
  private func calculateHashForArray(array: [AnyHashable]) -> Int {
    var result: Int = 1
    let prime: Int = 31
    
    for value in array {
      let valueHash: Int = calculateHashForValue(value: value)
      result = prime &* result &+ valueHash
    }
    
    return result
  }

  private func calculateHashForValue(value: AnyHashable) -> Int {
    var valueHash: Int = 0
    
    if let dictValue = value as? [String: AnyHashable] {
      valueHash = calculateHashForDictionary(dict: dictValue)
    } else if let arrayValue = value as? [AnyHashable] {
      valueHash = calculateHashForArray(array: arrayValue)
    } else {
      valueHash = value.hashValue
    }
    
    return valueHash
  }
}
