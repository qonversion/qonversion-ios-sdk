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
    
    init(baseURL: String, networkProvider: NetworkProvider, headersBuilder: HeadersBuilderInterface, errorHandler: NetworkErrorHandler, decoder: ResponseDecoderInterface) {
        self.baseURL = baseURL
        self.networkProvider = networkProvider
        self.headersBuilder = headersBuilder
        self.errorHandler = errorHandler
        self.decoder = decoder
    }
    
    func process<T>(request: Request, responseType: T.Type) async throws -> T? where T : Decodable {
        guard let urlRequest: URLRequest = request.convertToURLRequest() else {
            throw QonversionError(type: .invalidRequest, message: "Invalud URL", error: nil, additionalInfo: nil)
        }
        
        do {
            let (data, resposne) = try await networkProvider.send(request: urlRequest)
            // handle Qonversion API specific errors here using errorHandler
            let result: T = try decoder.decode(responseType, from: data)
            
            return result
        } catch {
            throw QonversionError(type: .invalidResponse, message: "Invalid response", error: error, additionalInfo: nil)
        }
    }
}
