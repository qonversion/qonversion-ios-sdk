//
//  RequestProcessor.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 06.02.2024.
//

class RequestProcessor: RequestProcessorInterface {
    let baseURL: String
    let networkProvider: NetworkProvider
    let headersBuilder: HeadersBuilderInterface
    let errorHandler: NetworkErrorHandler
    let decoder: ResponseDecoderInterface
    let rateLimiter: RateLimiter
    
    init(
        baseURL: String,
        networkProvider: NetworkProvider,
        headersBuilder: HeadersBuilderInterface,
        errorHandler: NetworkErrorHandler,
        decoder: ResponseDecoderInterface,
        rateLimiter: RateLimiter
    ) {
        self.baseURL = baseURL
        self.networkProvider = networkProvider
        self.headersBuilder = headersBuilder
        self.errorHandler = errorHandler
        self.decoder = decoder
        self.rateLimiter = rateLimiter
    }
    
    func process<T>(request: Request, responseType: T.Type) async throws -> T? where T : Decodable {
        if let rateLimitError = rateLimiter.validateRateLimit(request: request) {
            throw rateLimitError
        }

        guard let urlRequest: URLRequest = request.convertToURLRequest() else {
            throw QonversionError(type: .invalidRequest, message: "Invalud URL", error: nil, additionalInfo: nil)
        }
        
        do {
            let (data, response) = try await networkProvider.send(request: urlRequest)
            // handle Qonversion API specific errors here using errorHandler
            do {
                let result: T = try decoder.decode(responseType, from: data)
                
                return result
            } catch {
                throw QonversionError(type: .invalidResponse, message: "Invalid response", error: error, additionalInfo: nil)
            }
        } catch {
            throw QonversionError(type: .invalidResponse, message: "Request failed", error: error, additionalInfo: nil)
        }
    }
}
