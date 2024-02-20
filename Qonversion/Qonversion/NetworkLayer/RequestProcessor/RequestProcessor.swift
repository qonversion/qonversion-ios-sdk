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
    let errorHandler: NetworkErrorHandlerInterface
    let decoder: ResponseDecoderInterface
    let retriableRequestsList: [Request]
    let requestsStorage: RequestsStorageInterface
    var criticalError: QonversionError?
    
    init(baseURL: String, networkProvider: NetworkProvider, headersBuilder: HeadersBuilderInterface, errorHandler: NetworkErrorHandlerInterface, decoder: ResponseDecoderInterface, retriableRequestsList: [Request], requestsStorage: RequestsStorageInterface, criticalError: QonversionError? = nil) {
        self.baseURL = baseURL
        self.networkProvider = networkProvider
        self.headersBuilder = headersBuilder
        self.errorHandler = errorHandler
        self.decoder = decoder
        self.retriableRequestsList = retriableRequestsList
        self.requestsStorage = requestsStorage
        self.criticalError = criticalError
        
        processStoredRequests()
    }
    
    func processStoredRequests() {
        let requests: [URLRequest] = requestsStorage.fetchRequests()
        let requestsCopy: [URLRequest] = requests
        
        #warning("Resend all requests here and remove from the storage")
        
        requestsStorage.clean()
    }
    
    func process<T>(request: Request, responseType: T.Type) async throws -> T? where T : Decodable {
        if let error = criticalError {
            throw error
        }
        
        guard let urlRequest: URLRequest = request.convertToURLRequest() else {
            let errorType: QonversionErrorType = .invalidRequest
            throw QonversionError(type: errorType, message: errorType.message())
        }
        
        do {
            let (data, resposne) = try await networkProvider.send(request: urlRequest)
            let error: QonversionError? = errorHandler.extractError(from: resposne)
            if error?.type == .critical {
                criticalError = error
            }
            
            guard error == nil else { throw error! }
            
            
            do {
                let result: T = try decoder.decode(responseType, from: data)
                
                return result
            } catch {
                let errorType: QonversionErrorType = .invalidResponse
                throw QonversionError(type: errorType, message: errorType.message(), error: error)
            }
        } catch {
            let errorType: QonversionErrorType = .invalidResponse
            throw QonversionError(type: errorType, message: errorType.message(), error: error)
        }
    }
}
