//
//  RequestProcessor.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 06.02.2024.
//

import Foundation

// @unchecked: the processor holds no mutable state of its own; every
// dependency is thread-safe.
class RequestProcessor: RequestProcessorInterface, @unchecked Sendable {
    let baseURL: String
    let networkProvider: NetworkProviderInterface
    let headersBuilder: HeadersBuilderInterface
    let errorHandler: NetworkErrorHandlerInterface
    let decoder: ResponseDecoderInterface
    let retriableRequestKinds: [Request.Kind]
    let requestsStorage: RequestsStorageInterface
    let rateLimiter: RateLimiterInterface
    private let delayCalculator: IncrementalDelayCalculator
    private let transportRetryDelayCeiling: TimeInterval
    /// Shared with the purchases manager: the launch replay and the
    /// unfinished-transaction sweep run concurrently and must not both post
    /// the same purchase.
    let reportsGate: TransactionReportsGate
    /// Shared with every other processor of the Qonversion target; NoCodes
    /// keeps its own.
    let criticalErrorLatch: CriticalErrorLatch

    var criticalError: QonversionError? {
        return criticalErrorLatch.error
    }

    init(baseURL: String, networkProvider: NetworkProviderInterface, headersBuilder: HeadersBuilderInterface, errorHandler: NetworkErrorHandlerInterface, decoder: ResponseDecoderInterface, retriableRequestKinds: [Request.Kind], requestsStorage: RequestsStorageInterface, rateLimiter: RateLimiterInterface, delayCalculator: IncrementalDelayCalculator = IncrementalDelayCalculator(), transportRetryDelayCeiling: TimeInterval = RequestProcessor.defaultTransportRetryDelayCeiling, reportsGate: TransactionReportsGate = TransactionReportsGate(), criticalErrorLatch: CriticalErrorLatch = CriticalErrorLatch()) {
        self.baseURL = baseURL
        self.networkProvider = networkProvider
        self.headersBuilder = headersBuilder
        self.errorHandler = errorHandler
        self.decoder = decoder
        self.retriableRequestKinds = retriableRequestKinds
        self.requestsStorage = requestsStorage
        self.rateLimiter = rateLimiter
        self.delayCalculator = delayCalculator
        self.transportRetryDelayCeiling = transportRetryDelayCeiling
        self.reportsGate = reportsGate
        self.criticalErrorLatch = criticalErrorLatch
    }

    /// Resends requests that failed on transport in previous sessions. A
    /// delivered request (an HTTP answer of any status — resending would
    /// duplicate) is removed from the queue one by one; a transport failure
    /// keeps it for the next session. A latched critical error (revoked
    /// project key) stops the replay without removing anything, so the entries
    /// wait for a launch where the key works again.
    ///
    /// A purchase report also passes through the shared reports gate, which the
    /// replay always hands back: released when the report did not land, marked
    /// reported when it did. The replay is an HTTP resend with no StoreKit
    /// context — it cannot finish the transaction or surface a deferred
    /// purchase, so the launch sweep must still be able to claim it.
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
                // The snapshot is not the queue: another path (the launch
                // sweep delivering the same purchase, a live report
                // superseding a queued copy) may have removed this entry while
                // the previous ones were in flight.
                guard self.requestsStorage.fetchRequests().contains(stored) else { continue }
                guard let url = URL(string: stored.url) else {
                    self.requestsStorage.remove(stored)
                    continue
                }

                // A purchase report is owned by whoever takes its transaction
                // id first — here or in the unfinished-transaction sweep that
                // initialize() starts alongside this replay. Entries queued by
                // an older build carry no transaction id; those rely on the
                // presence check above, which the sweep triggers by evicting
                // the queued copy when its own report is delivered.
                let transactionId: String? = stored.transactionId
                if let transactionId, !self.reportsGate.tryTake(transactionId) {
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
                    let responseError: QonversionError? = self.errorHandler.extractError(from: urlResponse, body: data)

                    // Checked before the entry is touched: a revoked project key
                    // stops the replay with the queue intact, so the entries
                    // wait for a launch where the key works again.
                    if let responseError, responseError.type == .critical {
                        if let transactionId {
                            self.reportsGate.release(transactionId)
                        }
                        self.criticalErrorLatch.latch(responseError)
                        return
                    }

                    // 5xx/429 mean the backend did not process the request —
                    // keep it queued. Everything else counts as delivered
                    // (resending would duplicate) or permanently rejected.
                    let statusCode = (urlResponse as? HTTPURLResponse)?.statusCode ?? 0
                    if Self.isRetriableStatusCode(statusCode) {
                        self.bumpAttempt(of: stored, ifGenerationIs: generation)
                        // Not delivered: let the next attempt (or the sweep)
                        // have the transaction back.
                        if let transactionId {
                            self.reportsGate.release(transactionId)
                        }
                    } else {
                        // Delivered. The replay cannot finish the StoreKit
                        // transaction nor surface it, so the id goes back to the
                        // sweep marked as reported — it completes the outcome
                        // without posting the purchase twice.
                        if let transactionId {
                            self.reportsGate.markReported(transactionId)
                        }
                        self.requestsStorage.remove(stored)
                    }
                } catch {
                    // Kept in the queue for the next session.
                    self.bumpAttempt(of: stored, ifGenerationIs: generation)
                    if let transactionId {
                        self.reportsGate.release(transactionId)
                    }
                }
            }
        }
    }
    
    static func isRetriableStatusCode(_ statusCode: Int) -> Bool {
        return statusCode >= 500 || statusCode == 429
    }

    /// Requests the SDK emits on its own schedule, which the host cannot spam.
    /// Offer signing is deliberately not here: it is public API, so its rate is
    /// the host's to set.
    static let rateLimitExemptKinds: [Request.Kind] = [.sendProperties]

    static let attemptHeader: String = "Attempt"
    static let triggerHeader: String = "Trigger"

    /// `attempt` is how many sends the request already cost, so the replay
    /// continues the Attempt sequence; `generation` pins the entry to the user
    /// it was made for, so a user switch landing in between is not undone.
    private func queueForReplay(_ request: Request, as urlRequest: URLRequest, trigger: RequestTrigger?, attempt: Int, ifGenerationIs generation: Int) {
        let stored = StoredRequest(
            url: urlRequest.url?.absoluteString ?? "",
            method: urlRequest.httpMethod ?? "POST",
            body: urlRequest.httpBody,
            dedupKey: request.replayDedupKey,
            trigger: trigger?.rawValue,
            attempt: attempt,
            transactionId: request.replayTransactionId
        )

        requestsStorage.append(stored, ifGenerationIs: generation)
    }

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
            // Queued before refusing, so data the store already charged for
            // survives a latched key. Reads carry nothing and are just refused.
            if retriableRequestKinds.contains(request.kind), let urlRequest: URLRequest = request.convertToURLRequest(baseURL) {
                // Nothing was sent, so the replay must report attempt 1.
                queueForReplay(request, as: urlRequest, trigger: trigger, attempt: 0, ifGenerationIs: requestsStorage.cleanGeneration)
            }

            throw error
        }

        if !Self.rateLimitExemptKinds.contains(request.kind) {
            if let rateLimitError: QonversionError = rateLimiter.validateRateLimit(for: request) {
                throw rateLimitError
            }
        }

        guard var urlRequest: URLRequest = request.convertToURLRequest(baseURL) else {
            throw QonversionError(type: .invalidRequest)
        }
        headersBuilder.addHeaders(to: &urlRequest)
        if let trigger {
            urlRequest.addValue(trigger.rawValue, forHTTPHeaderField: Self.triggerHeader)
        }

        // The queue any failure of this request lands in belongs to the user
        // it is being sent for: a clean() while it is in flight (user switch)
        // must not be undone by re-queueing it afterwards.
        let generation: Int = requestsStorage.cleanGeneration

        // The in-session retries already burned attempts against this request;
        // a copy queued afterwards must continue that count, not restart it,
        // or the Attempt header lies to the backend on every replay.
        let attemptsMade = AttemptCounter()

        let responseBody: Data
        let error: QonversionError?
        let responseCode: Int
        do {
            let (data, urlResponse) = try await sendWithTransportRetries(urlRequest, attemptsMade: attemptsMade)
            error = errorHandler.extractError(from: urlResponse, body: data)
            responseBody = data
            responseCode = (urlResponse as? HTTPURLResponse)?.statusCode ?? 0
        } catch {
            // Only a transport failure proves the request never reached the
            // backend. A cancelled send may well have been processed, so
            // queueing it would report the same purchase twice (ObjC parity:
            // QNAPIClient.m queued strictly on [QNUtils isConnectionError:]).
            let isTransportFailure: Bool = Self.isTransportFailure(error)
            if isTransportFailure, retriableRequestKinds.contains(request.kind) {
                queueForReplay(request, as: urlRequest, trigger: trigger, attempt: attemptsMade.total, ifGenerationIs: generation)
            }
            // Named for what it is, so the host can branch on "offline"
            // instead of on a broken response.
            let type: QonversionErrorType = isTransportFailure ? .networkConnectionFailed : .invalidResponse
            throw QonversionError(type: type, error: error)
        }

        guard error == nil else {
            let latchesCriticalError: Bool = error?.type == .critical
            if let error, latchesCriticalError {
                criticalErrorLatch.latch(error)
            }

            // The backend did not process the request (5xx/429) — persist
            // retriable ones for the offline replay, like transport failures.
            // A revoked key (401/402/403) is queued too: every request AFTER
            // the latch is, and the one that tripped it carries data the store
            // already charged for.
            if (Self.isRetriableStatusCode(responseCode) || latchesCriticalError) && retriableRequestKinds.contains(request.kind) {
                queueForReplay(request, as: urlRequest, trigger: trigger, attempt: attemptsMade.total, ifGenerationIs: generation)
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
            // Only within the generation this request was sent for: after a
            // user switch the queued copy of the same transaction belongs to
            // the NEW user and this delivery says nothing about it.
            requestsStorage.removeAll(ifGenerationIs: generation) { stored in
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

    // MARK: - Transport retries

    /// How many times a connection-class failure is resent inside the call that
    /// produced it — four sends in total, the first one included. Matches the
    /// ObjC client, which resent up to three times (QNAPIClient.m:523-551,
    /// `tryCount < 3`) before giving up and handing the request to the offline
    /// queue.
    static let maxTransportRetries: Int = 3

    /// The in-session backoff is capped: the caller is usually blocked on this
    /// request (a purchase report, a paywall load), so a network that is
    /// genuinely down must fail fast enough to be handled, not hang the flow.
    /// The ObjC client retried with no delay at all.
    static let defaultTransportRetryDelayCeiling: TimeInterval = 2

    /// Counts the sends one process() call made, so a request queued after the
    /// in-session retries continues the true attempt sequence.
    // @unchecked: the counter is lock-guarded; the retry loop and the caller
    // touch it from the same task, the lock is belt and braces.
    final class AttemptCounter: @unchecked Sendable {

        private let lock = NSLock()
        private var _total: Int = 0

        var total: Int {
            lock.lock()
            defer { lock.unlock() }
            return max(_total, 1)
        }

        func record(_ attempt: Int) {
            lock.lock()
            _total = max(_total, attempt)
            lock.unlock()
        }
    }

    /// A failure with no response at all: the request never reached the
    /// backend, so resending it cannot duplicate anything. The connection-class
    /// URLErrors, plus the extra codes the ObjC client also treated as "no
    /// transport" (QNUtils.m:106-116).
    static func isTransportFailure(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }

        switch urlError.code {
        case .notConnectedToInternet, .timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed,
             .callIsActive, .dataNotAllowed,
             // CFNetwork reports an offline name lookup as -1003 far more often
             // than as -1006, and a TLS handshake that never completed carries
             // no response either.
             .cannotFindHost, .secureConnectionFailed:
            return true
        default:
            return false
        }
    }

    /// Retries ONLY when no response was received. Once the backend answered —
    /// with any status — the request is delivered and resending it would
    /// duplicate the work; those statuses are handled by the caller and, for
    /// the retriable kinds, by the offline queue.
    ///
    /// The rate limiter and the critical-error latch are deliberately outside
    /// this loop: a retry is not a new call.
    private func sendWithTransportRetries(_ request: URLRequest, attemptsMade: AttemptCounter) async throws -> (Data, URLResponse) {
        var attempt: Int = 1
        var attemptedRequest: URLRequest = request

        while true {
            // Like the ObjC client, the backend is told which attempt this is.
            attemptedRequest.setValue("\(attempt)", forHTTPHeaderField: Self.attemptHeader)
            attemptsMade.record(attempt)

            do {
                return try await networkProvider.send(request: attemptedRequest)
            } catch let transportError {
                guard attempt <= Self.maxTransportRetries, Self.isTransportFailure(transportError) else { throw transportError }

                do {
                    try await waitBeforeRetry(number: attempt)
                } catch {
                    // Cancelled while backing off: surface the transport
                    // failure rather than the CancellationError, or the host
                    // loses its "offline" branch and the local fallback.
                    throw transportError
                }
                attempt += 1
            }
        }
    }

    private func waitBeforeRetry(number: Int) async throws {
        guard transportRetryDelayCeiling > 0 else { return }

        let calculated: Int = delayCalculator.countDelay(minDelay: 0, retriesCount: number)
        let delay: TimeInterval = min(TimeInterval(calculated), transportRetryDelayCeiling)
        guard delay > 0 else { return }

        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
}
