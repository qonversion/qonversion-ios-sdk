//
//  NetworkErrorHandler.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 07.02.2024.
//

import Foundation

#if os(iOS)

class NetworkErrorHandler: NetworkErrorHandlerInterface {
    
    let criticalErrorCodes: [ResponseCode]
    let decoder: ResponseDecoderInterface

    init(criticalErrorCodes: [ResponseCode], decoder: ResponseDecoderInterface) {
        self.criticalErrorCodes = criticalErrorCodes
        self.decoder = decoder
    }

    func extractError(from response: URLResponse, body: Data) -> NoCodesError? {
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

    private func configureError(for response: HTTPURLResponse, body: Data, type: NoCodesErrorType, error: Error? = nil, additionalInfo: [String: Any]? = nil) -> NoCodesError {
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
            info[ErrorConstants.messageKey.rawValue] = HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
        }

        return NoCodesError(type: type, message: apiErrorWrapper?.error.message, error: error, additionalInfo: info)
    }
}

#endif
