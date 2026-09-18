//
//  NetworkProvider.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 02.02.2024.
//

import Foundation

#if os(iOS)

class NetworkProvider: NetworkProviderInterface {
  private(set) var session: URLSession

  init(timeout: TimeInterval?) {
    let config = URLSessionConfiguration.default
    if let timeout = timeout {
      config.timeoutIntervalForRequest = timeout
      config.timeoutIntervalForResource = timeout
    }
    session = URLSession(configuration: config)
  }

  init() {
    session = URLSession(configuration: .default)
  }

  func send(request: URLRequest) async throws -> (Data, URLResponse) {
    return try await withCheckedThrowingContinuation { continuation in
      session.dataTask(with: request) { data, response, error in
        if let error = error {
          continuation.resume(throwing: error)
        } else if let data = data, let response = response {
          continuation.resume(returning: (data, response))
        } else {
          continuation.resume(throwing: NSError(domain: "NetworkProvider", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
        }
      }.resume()
    }
  }
}

#endif
