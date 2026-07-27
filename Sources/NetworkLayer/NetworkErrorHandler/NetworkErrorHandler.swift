//
//  NetworkErrorHandler.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 07.02.2024.
//

import Foundation

// @unchecked: the decoder and code list are read-only after init.
final class NetworkErrorHandler: NetworkErrorHandlerInterface, @unchecked Sendable {
    
    let criticalErrorCodes: [ResponseCode]
    let decoder: ResponseDecoderInterface

    init(criticalErrorCodes: [ResponseCode], decoder: ResponseDecoderInterface) {
        self.criticalErrorCodes = criticalErrorCodes
        self.decoder = decoder
    }

    func extractError(from response: URLResponse, body: Data) -> QonversionError? {
        guard let httpResponse = response as? HTTPURLResponse else { return nil }

        if (ResponseCode.internalErrorMin.rawValue...ResponseCode.internalErrorMax.rawValue).contains(httpResponse.statusCode) {
            return configureError(for: httpResponse, body: body, type: .internal)
        } else if criticalErrorCodes.map({ $0.rawValue }).contains(httpResponse.statusCode) {
            return configureError(for: httpResponse, body: body, type: .critical)
        } else if !(ResponseCode.successMin.rawValue...ResponseCode.successMax.rawValue).contains(httpResponse.statusCode) {
            return configureError(for: httpResponse, body: body, type: .unknown)
        }

        return nil
    }

    private func configureError(for response: HTTPURLResponse, body: Data, type: QonversionErrorType, error: Error? = nil, additionalInfo: [String: Any]? = nil) -> QonversionError {
        var info: [String: Any] = [:]

        let apiErrorWrapper: ApiErrorWrapper?
        do {
            apiErrorWrapper = try decoder.decode(ApiErrorWrapper.self, from: body)
        } catch {
            apiErrorWrapper = nil
        }

        if let additionalInfo {
            info = additionalInfo
        } else {
            // Fallback for bodies without the API error payload: at least the
            // standard reason phrase for the status code.
            info[ErrorConstants.messageKey.rawValue] = HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
        }
        info[ErrorConstants.statusCodeKey.rawValue] = response.statusCode

        // A body without an API message must not degrade to "Unknown error
        // occurred." — the status reason phrase is what the integrator needs.
        // The message is optional on the envelope, so an error body that
        // carries only the code and the v4 "details" array still maps.
        let apiError: ApiError? = apiErrorWrapper?.error
        let apiCode: String? = apiError?.code
        let apiMessage: String? = apiError.flatMap { $0.message }
        let message: String = apiMessage ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
        // A specific backend code refines the status-derived classification.
        // Critical (401/402/403) and server (5xx) types keep their meaning:
        // they drive the key-revocation latch and the offline fallback.
        let refinedType: QonversionErrorType = type == .unknown ? (QonversionErrorType(apiCode: apiCode) ?? type) : type

        return QonversionError(type: refinedType, message: message, error: error, additionalInfo: info, apiCode: apiCode, apiType: apiError?.type)
    }
}
