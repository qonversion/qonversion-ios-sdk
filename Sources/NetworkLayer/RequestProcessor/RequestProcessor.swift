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

        // The snapshot belongs to the user it was fetched for: a clean() in
        // between (user switch) invalidates every entry still in it.
        let generation: Int = requestsStorage.cleanGeneration

        // Strong capture on purpose: the caller does not retain this
        // processor, and a weak capture would let it deallocate before the
        // task runs — the replay would silently do nothing. The task holds
        // the processor exactly until the replay finishes.
        Task {
            for stored in requests {
                guard self.criticalError == nil else { return }
                guard self.requestsStorage.cleanGeneration == generation else { return }
                guard let url = URL(string: stored.url) else {
                    self.requestsStorage.remove(stored)
                    continue
                }

                var urlRequest = URLRequest(url: url)
                urlRequest.httpMethod = stored.method
                urlRequest.httpBody = stored.body
                self.headersBuilder.addHeaders(to: &urlRequest)
                urlRequest.addValue("\(stored.attempt + 1)", forHTTPHeaderField: Self.attemptHeader)
                if let trigger: String = stored.trigger {
                    urlRequest.addValue(trigger, forHTTPHeaderField: Self.triggerHeader)
                }

                do {
                    let (data, urlResponse) = try await self.networkProvider.send(request: urlRequest)

                    // 5xx/429 mean the backend did not process the request —
                    // keep it queued. Everything else counts as delivered
                    // (resending would duplicate) or permanently rejected.
                    let statusCode = (urlResponse as? HTTPURLResponse)?.statusCode ?? 0
                    if Self.isRetriableStatusCode(statusCode) {
                        self.bumpAttempt(of: stored, ifGenerationIs: generation)
                    } else {
                        self.requestsStorage.remove(stored)
                    }

                    if let error = self.errorHandler.extractError(from: urlResponse, body: data), error.type == .critical {
                        self.criticalError = error
                        return
                    }
                } catch {
                    // Kept in the queue for the next session.
                    self.bumpAttempt(of: stored, ifGenerationIs: generation)
                }
            }
        }
    }
    
    static func isRetriableStatusCode(_ statusCode: Int) -> Bool {
        return statusCode >= 500 || statusCode == 429
    }

    static let attemptHeader: String = "Attempt"
    static let triggerHeader: String = "Trigger"

    /// Records one more failed send of a queued request, so the next replay
    /// reports the true attempt number. A queue cleaned while the request was
    /// in flight must stay clean — the entry belongs to the previous user.
    private func bumpAttempt(of stored: StoredRequest, ifGenerationIs generation: Int) {
        let updated = StoredRequest(
            url: stored.url,
            method: stored.method,
            body: stored.body,
            dedupKey: stored.dedupKey,
            trigger: stored.trigger,
            attempt: stored.attempt + 1,
            transactionId: stored.transactionId
        )
        // One atomic step: a check followed by a separate remove and append
        // leaves two windows for a clean() to be undone.
        requestsStorage.replace(stored, with: updated, ifGenerationIs: generation)
    }

    func process<T>(request: Request, responseType: T.Type, trigger: RequestTrigger?) async throws -> T where T : Decodable {
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
        urlRequest.addValue("1", forHTTPHeaderField: Self.attemptHeader)
        if let trigger {
            urlRequest.addValue(trigger.rawValue, forHTTPHeaderField: Self.triggerHeader)
        }

        // The queue any failure of this request lands in belongs to the user
        // it is being sent for: a clean() while it is in flight (user switch)
        // must not be undone by re-queueing it afterwards.
        let generation: Int = requestsStorage.cleanGeneration

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
                let stored = StoredRequest(
                    url: urlRequest.url?.absoluteString ?? "",
                    method: urlRequest.httpMethod ?? "POST",
                    body: urlRequest.httpBody,
                    dedupKey: request.replayDedupKey,
                    trigger: trigger?.rawValue,
                    transactionId: request.replayTransactionId
                )
                requestsStorage.append(stored, ifGenerationIs: generation)
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
                let stored = StoredRequest(
                    url: urlRequest.url?.absoluteString ?? "",
                    method: urlRequest.httpMethod ?? "POST",
                    body: urlRequest.httpBody,
                    dedupKey: request.replayDedupKey,
                    trigger: trigger?.rawValue,
                    transactionId: request.replayTransactionId
                )
                requestsStorage.append(stored, ifGenerationIs: generation)
            }

            throw error!
        }
        
        // No-response requests tolerate any 2xx with an empty body, exactly
        // like production: the backend acknowledged, there is nothing to parse.
        if T.self is EmptyApiResponse.Type && (responseCode == ResponseCode.noContent.rawValue || ((200...299).contains(responseCode) && responseBody.isEmpty)) {
            return EmptyApiResponse() as! T
        }
        
        // A delivered purchase report supersedes any queued copy of the same
        // transaction (it may sit under the previous uid) — replaying it on
        // the next launch would double-report the purchase.
        if request.kind == .createPurchase, let transactionId: String = request.replayTransactionId {
            requestsStorage.removeAll { stored in
                if let storedTransactionId: String = stored.transactionId {
                    return storedTransactionId == transactionId
                }

                // Entries queued by an older build carry no transaction id:
                // fall back to an ANCHORED dedup key match, so a uid that ends
                // in "-<transactionId>" cannot evict an unrelated purchase.
                guard let dedupKey: String = stored.dedupKey else { return false }

                return dedupKey.hasPrefix("createPurchase-") && dedupKey.hasSuffix("-" + transactionId)
            }
        }

        do {
            let result: T = try decoder.decode(responseType, from: responseBody)

            return result
        } catch {
            throw QonversionError(type: .invalidResponse, error: error)
        }
    }
}
