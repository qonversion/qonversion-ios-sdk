//
//  CrashReportsTransport.swift
//  Qonversion
//

import Foundation

/// What one send of a crash report ended up as. The service answers with a
/// body this SDK does not parse, so the status line is the whole verdict.
enum CrashReportDelivery {
    /// Any 2xx — the service took it.
    case delivered
    /// The service answered something else. It saw the payload; a resend is
    /// unlikely to change that, so the report's attempt budget pays for it.
    case rejected
    /// No answer at all. Says nothing about the report, and every following
    /// send this launch would fail the same way.
    case notReached
}

protocol CrashReportsTransportInterface: Sendable {
    func send(body: RequestBodyDict) async -> CrashReportDelivery
}

/// Ships crash payloads to the sdk-logs service, which is a different host from
/// the main processor's: no project key header, no error envelope, no response
/// to parse. Consequently none of the main processor's machinery — the critical
/// error latch, the rate limiter, the offline replay queue — applies here.
final class CrashReportsTransport: CrashReportsTransportInterface {

    /// The host the ObjC SDK has always shipped crashes to.
    static let defaultBaseURL: String = "https://sdk-logs.qonversion.io/"
    private static let endpoint: String = "sdk.log"
    private static let successRange: ClosedRange<Int> = 200...299

    private let networkProvider: NetworkProviderInterface
    private let baseURL: String

    init(networkProvider: NetworkProviderInterface, baseURL: String = CrashReportsTransport.defaultBaseURL) {
        self.networkProvider = networkProvider
        self.baseURL = baseURL
    }

    func send(body: RequestBodyDict) async -> CrashReportDelivery {
        guard let url = URL(string: baseURL + Self.endpoint),
              let httpBody: Data = try? JSONSerialization.data(withJSONObject: body) else {
            // Nothing sendable was built, and the next launch would build the
            // same thing: spend an attempt rather than retry forever.
            return .rejected
        }

        var request = URLRequest(url: url)
        request.httpMethod = RequestType.post.rawValue
        request.setValue("application/json", forHTTPHeaderField: Header.contentType.rawValue)
        request.httpBody = httpBody

        guard let (_, response) = try? await networkProvider.send(request: request) else { return .notReached }
        guard let statusCode: Int = (response as? HTTPURLResponse)?.statusCode else { return .notReached }

        return Self.successRange.contains(statusCode) ? .delivered : .rejected
    }
}
