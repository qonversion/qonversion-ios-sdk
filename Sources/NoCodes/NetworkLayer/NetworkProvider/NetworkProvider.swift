//
//  NetworkProvider.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 02.02.2024.
//

import Foundation

#if os(iOS)

class NetworkProvider: NSObject, NetworkProviderInterface, URLSessionDelegate {
  private(set) var session: URLSession!

  init(timeout: TimeInterval?) {
    super.init()
    let config = URLSessionConfiguration.default
    if let timeout = timeout {
      config.timeoutIntervalForRequest = timeout
      config.timeoutIntervalForResource = timeout
    }
    session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
  }

  override init() {
    super.init()
    session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
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

  // MARK: - Temporary SSL bypass for staging. Remove before release.
  func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
    if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
       let serverTrust = challenge.protectionSpace.serverTrust {
      completionHandler(.useCredential, URLCredential(trust: serverTrust))
    } else {
      completionHandler(.performDefaultHandling, nil)
    }
  }
}

#endif
