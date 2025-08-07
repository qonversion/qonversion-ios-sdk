//
//  NetworkProvider.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 02.02.2024.
//

import Foundation

#if os(iOS)

class NetworkProvider: NetworkProviderInterface {
  let session: URLSession
  
  init(session: URLSession) {
    self.session = session
  }
  
  convenience init(timeout: TimeInterval?) {
    let config = URLSessionConfiguration.default
    timeout.map {
      config.timeoutIntervalForRequest = $0
      config.timeoutIntervalForResource = $0
    }
    let session = URLSession(configuration: config)
    self.init(session: session)
  }
  
  func send(request: URLRequest) async throws -> (Data, URLResponse) {
    if #available(macOS 12.0, *) {
      return try await session.data(for: request)
    } else {
      // Fallback for older macOS versions
      return try await withCheckedThrowingContinuation { continuation in
        let task = session.dataTask(with: request) { data, response, error in
          if let error = error {
            continuation.resume(throwing: error)
          } else if let data = data, let response = response {
            continuation.resume(returning: (data, response))
          } else {
            continuation.resume(throwing: NSError(domain: "NetworkProvider", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
          }
        }
        task.resume()
      }
    }
  }
}

#endif
