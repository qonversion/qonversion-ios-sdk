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
    let requestsStorage: RequestsStorageInterface
    let rateLimiter: RateLimiterInterface
    var criticalError: QonversionError?

    init(baseURL: String, networkProvider: NetworkProviderInterface, headersBuilder: HeadersBuilderInterface, errorHandler: NetworkErrorHandlerInterface, decoder: ResponseDecoderInterface, retriableRequestsList: [Request], requestsStorage: RequestsStorageInterface, rateLimiter: RateLimiterInterface) {
        self.baseURL = baseURL
        self.networkProvider = networkProvider
        self.headersBuilder = headersBuilder
        self.errorHandler = errorHandler
        self.decoder = decoder
        self.retriableRequestsList = retriableRequestsList
        self.requestsStorage = requestsStorage
        self.rateLimiter = rateLimiter
        
        processStoredRequests()
    }
    
    func processStoredRequests() {
        let requests: [URLRequest] = requestsStorage.fetchRequests()
        let requestsCopy: [URLRequest] = requests
        
        #warning("Resend all requests here and remove from the storage")
        
        requestsStorage.clean()
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
        do {
            let (data, urlResponse) = try await networkProvider.send(request: urlRequest)
            error = errorHandler.extractError(from: urlResponse)
            responseBody = data
        } catch {
            throw QonversionError(type: .invalidResponse, error: error)
        }

        guard error == nil else {
            if error?.type == .critical {
                criticalError = error
            }

            throw error!
        }

        do {
            let result: T = try decoder.decode(responseType, from: responseBody)

            return result
        } catch {
            throw QonversionError(type: .invalidResponse, error: error)
        }
    }
}