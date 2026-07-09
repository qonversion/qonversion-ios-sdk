//
//  RequestProcessor.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 06.02.2024.
//

import Foundation

// @unchecked: criticalError is the only mutable field and is lock-guarded;
// every dependency is thread-safe on its own.
class RequestProcessor: RequestProcessorInterface, @unchecked Sendable {
    let baseURL: String
    let networkProvider: NetworkProviderInterface
    let headersBuilder: HeadersBuilderInterface
    let errorHandler: NetworkErrorHandlerInterface
    let decoder: ResponseDecoderInterface
    let retriableRequestKinds: [Request.Kind]
    let requestsStorage: RequestsStorageInterface
    let rateLimiter: RateLimiterInterface
    private let criticalErrorLock = NSLock()
    private var _criticalError: QonversionError?

    var criticalError: QonversionError? {
        get {
            criticalErrorLock.lock()
            defer { criticalErrorLock.unlock() }
            return _criticalError
        }
        set {
            criticalErrorLock.lock()
            defer { criticalErrorLock.unlock() }
            _criticalError = newValue
        }
    }

    init(baseURL: String, networkProvider: NetworkProviderInterface, headersBuilder: HeadersBuilderInterface, errorHandler: NetworkErrorHandlerInterface, decoder: ResponseDecoderInterface, retriableRequestKinds: [Request.Kind], requestsStorage: RequestsStorageInterface, rateLimiter: RateLimiterInterface) {
        self.baseURL = baseURL
        self.networkProvider = networkProvider
        self.headersBuilder = headersBuilder
        self.errorHandler = errorHandler
        self.decoder = decoder
        self.retriableRequestKinds = retriableRequestKinds
        self.requestsStorage = requestsStorage
        self.rateLimiter = rateLimiter
    }

    /// Resends requests that failed on transport in previous sessions. A
    /// delivered request (an HTTP answer of any status — resending would
    /// duplicate) is removed from the queue one by one; a transport failure
    /// keeps it for the next session. A latched critical error (revoked
    /// project key) stops the replay.
    func processStoredRequests() {
        guard criticalError == nil else { return }

        let requests: [StoredRequest] = requestsStorage.fetchRequests()
        guard !requests.isEmpty else { return }

        Task { [weak self] in
            for stored in requests {
                guard let self, self.criticalError == nil else { return }
                guard let url = URL(string: stored.url) else {
                    self.requestsStorage.remove(stored)
                    continue
                }

                var urlRequest = URLRequest(url: url)
                urlRequest.httpMethod = stored.method
                urlRequest.httpBody = stored.body
                self.headersBuilder.addHeaders(to: &urlRequest)

                do {
                    let (data, urlResponse) = try await self.networkProvider.send(request: urlRequest)

                    // 5xx/429 mean the backend did not process the request —
                    // keep it queued. Everything else counts as delivered
                    // (resending would duplicate) or permanently rejected.
                    let statusCode = (urlResponse as? HTTPURLResponse)?.statusCode ?? 0
                    if !Self.isRetriableStatusCode(statusCode) {
                        self.requestsStorage.remove(stored)
                    }

                    if let error = self.errorHandler.extractError(from: urlResponse, body: data), error.type == .critical {
                        self.criticalError = error
                        return
                    }
                } catch {
                    // Kept in the queue for the next session.
                }
            }
        }
    }
    
    static func isRetriableStatusCode(_ statusCode: Int) -> Bool {
        return statusCode >= 500 || statusCode == 429
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
            responseCode = (urlResponse as? HTTPURLResponse)?.statusCode ?? 0
        } catch {
            // The request never reached the backend — persist retriable ones
            // for the offline replay.
            if retriableRequestKinds.contains(request.kind) {
                requestsStorage.append(StoredRequest(
                    url: urlRequest.url?.absoluteString ?? "",
                    method: urlRequest.httpMethod ?? "POST",
                    body: urlRequest.httpBody,
                    dedupKey: request.replayDedupKey
                ))
            }
            throw QonversionError(type: .invalidResponse, error: error)
        }

        guard error == nil else {
            if error?.type == .critical {
                criticalError = error
            }

            // The backend did not process the request (5xx/429) — persist
            // retriable ones for the offline replay, like transport failures.
            if Self.isRetriableStatusCode(responseCode) && retriableRequestKinds.contains(request.kind) {
                requestsStorage.append(StoredRequest(
                    url: urlRequest.url?.absoluteString ?? "",
                    method: urlRequest.httpMethod ?? "POST",
                    body: urlRequest.httpBody,
                    dedupKey: request.replayDedupKey
                ))
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
