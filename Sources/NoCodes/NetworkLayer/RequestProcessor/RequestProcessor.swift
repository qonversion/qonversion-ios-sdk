//
//  RequestProcessor.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 06.02.2024.
//

import Foundation

// @unchecked: the only mutable state is `_criticalError`, guarded by
// `criticalErrorLock` on every read and write.
final class RequestProcessor: RequestProcessorInterface, @unchecked Sendable {
  let baseURL: String
  let networkProvider: NetworkProviderInterface
  let headersBuilder: HeadersBuilderInterface
  let errorHandler: NetworkErrorHandlerInterface
  let decoder: ResponseDecoderInterface
  let rateLimiter: RateLimiterInterface

  // Sticky by design: a rejected project key fails every later request too.
  // The lock is held only around the property access, never across an await.
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
      // Any empty-bodied 2xx counts as acknowledged, not only a 204.
      let isSuccess: Bool = (ResponseCode.successMin.rawValue...ResponseCode.successMax.rawValue).contains(responseCode)
      let isAcknowledgedWithoutBody: Bool = responseCode == ResponseCode.noContent.rawValue || (isSuccess && responseBody.isEmpty)
      if isAcknowledgedWithoutBody, let empty = EmptyApiResponse() as? T {
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
