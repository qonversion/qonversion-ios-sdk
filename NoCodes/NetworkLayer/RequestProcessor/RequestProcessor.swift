//
//  RequestProcessor.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 06.02.2024.
//

import Foundation

class RequestProcessor: RequestProcessorInterface {
  let baseURL: String
  let networkProvider: NetworkProviderInterface
  let headersBuilder: HeadersBuilderInterface
  let errorHandler: NetworkErrorHandlerInterface
  let decoder: ResponseDecoderInterface
  let retriableRequestsList: [Request]
  let rateLimiter: RateLimiterInterface
  var criticalError: QonversionError?
  
  init(baseURL: String, networkProvider: NetworkProviderInterface, headersBuilder: HeadersBuilderInterface, errorHandler: NetworkErrorHandlerInterface, decoder: ResponseDecoderInterface, retriableRequestsList: [Request], rateLimiter: RateLimiterInterface) {
    self.baseURL = baseURL
    self.networkProvider = networkProvider
    self.headersBuilder = headersBuilder
    self.errorHandler = errorHandler
    self.decoder = decoder
    self.retriableRequestsList = retriableRequestsList
    self.rateLimiter = rateLimiter
  }
  
  func process<T>(request: Request, responseType: T.Type) async throws -> T where T : Decodable {
    if let error = criticalError {
      throw error
    }
    
    if let rateLimitError: QonversionError = rateLimiter.validateRateLimit(for: request) {
      throw rateLimitError
    }
    
    guard var urlRequest: URLRequest = request.convertToURLRequest(baseURL) else {
      throw QonversionError(type: .invalidRequest)
    }
    headersBuilder.addHeaders(to: &urlRequest)
    
    let responseBody: Data
    let error: QonversionError?
    let responseCode: Int
    do {
      let (data, urlResponse) = try await networkProvider.send(request: urlRequest)
      error = errorHandler.extractError(from: urlResponse, body: data)
      responseBody = data
//      id dict = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&jsonError];
      let f = try JSONSerialization.jsonObject(with: data, options: [])
      responseCode = (urlResponse as? HTTPURLResponse)?.statusCode ?? 0
//      print(f)
    } catch {
      throw QonversionError(type: .invalidResponse, error: error)
    }
    
    guard error == nil else {
      if error?.type == .critical {
        criticalError = error
      }
      
      throw error!
    }
    
    if responseCode == ResponseCode.noContent.rawValue && T.self is EmptyApiResponse.Type {
      return EmptyApiResponse() as! T
    }
    
    do {
      let result: T = try decoder.decode(responseType, from: responseBody)
      
      return result
    } catch {
      throw QonversionError(type: .invalidResponse, error: error)
    }
  }
}
