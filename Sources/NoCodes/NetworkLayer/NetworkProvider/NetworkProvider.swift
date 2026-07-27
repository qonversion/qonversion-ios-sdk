//
//  NetworkProvider.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 02.02.2024.
//

import Foundation

// No URLSessionDelegate: the session must use the system's default server
// trust evaluation. Any custom authentication-challenge handling here would
// weaken TLS for every No-Codes request.
final class NetworkProvider: NetworkProviderInterface, Sendable {
  let session: URLSession

  init(timeout: TimeInterval?) {
    let config: URLSessionConfiguration = URLSessionConfiguration.default
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
          let userInfo: [String: String] = [NSLocalizedDescriptionKey: "Invalid response"]
          let error = NSError(domain: "NetworkProvider", code: -1, userInfo: userInfo)
          continuation.resume(throwing: error)
        }
      }.resume()
    }
  }
}
