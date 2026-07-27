//
//  RequestProcessor.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 06.02.2024.
//

import Foundation

class RequestProcessor: RequestProcessorInterface {
  var baseURL: String
  let networkProvider: NetworkProviderInterface
  let headersBuilder: HeadersBuilderInterface
  let errorHandler: NetworkErrorHandlerInterface
  let decoder: ResponseDecoderInterface
  let rateLimiter: RateLimiterInterface

  // Sticky by design: once the project key is rejected (401/402/403) every
  // later request would fail the same way, so the processor short-circuits.
  // Concurrent requests read and latch it, hence the lock — held only around
  // the property access, never across an await.
  private let criticalErrorLock = NSLock()
  private var _criticalError: NoCodesError?

  var criticalError: NoCodesError? {
    criticalErrorLock.lock()
    defer { criticalErrorLock.unlock() }

    return _criticalError
  }

  init(baseURL: String, networkProvider: NetworkProviderInterface, headersBuilder: HeadersBuilderInterface, errorHandler: NetworkErrorHandlerInterface, decoder: ResponseDecoderInterface, rateLimiter: RateLimiterInterface) {
    self.baseURL = baseURL
    self.networkProvider = networkProvider
    self.headersBuilder = headersBuilder
    self.errorHandler = errorHandler
    self.decoder = decoder
    self.rateLimiter = rateLimiter
  }

  func process<T>(request: Request, responseType: T.Type) async throws -> T where T : Decodable {
    if let error: NoCodesError = criticalError {
      throw error
    }

    if let rateLimitError: NoCodesError = rateLimiter.validateRateLimit(for: request) {
      throw rateLimitError
    }

    guard var urlRequest: URLRequest = request.convertToURLRequest(baseURL) else {
      throw NoCodesError(type: .invalidRequest)
    }
    headersBuilder.addHeaders(to: &urlRequest)

    let responseBody: Data
    let error: NoCodesError?
    let responseCode: Int
    do {
      let (data, urlResponse) = try await networkProvider.send(request: urlRequest)
      error = errorHandler.extractError(from: urlResponse, body: data)
      responseBody = data
      responseCode = (urlResponse as? HTTPURLResponse)?.statusCode ?? 0
    } catch {
      throw NoCodesError(type: .invalidResponse, error: error)
    }

    guard let error else {
      if responseCode == ResponseCode.noContent.rawValue, let empty = EmptyApiResponse() as? T {
        return empty
      }

      do {
        let result: T = try decoder.decode(responseType, from: responseBody)

        return result
      } catch {
        throw NoCodesError(type: .invalidResponse, error: error)
      }
    }

    if error.type == .critical {
      latch(criticalError: error)
    }

    throw error
  }

  private func latch(criticalError: NoCodesError) {
    criticalErrorLock.lock()
    defer { criticalErrorLock.unlock() }

    _criticalError = criticalError
  }
}
