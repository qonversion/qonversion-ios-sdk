//
//  NetworkErrorHandler.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 07.02.2024.
//

class NetworkErrorHandler: NetworkErrorHandlerInterface {
    
    let criticalErrorCodes: [ResponseCode]
    
    init(criticalErrorCodes: [ResponseCode]) {
        self.criticalErrorCodes = criticalErrorCodes
    }
    
    func extractError(from response: URLResponse) -> QonversionError? {
        guard let httpResponse = response as? HTTPURLResponse else { return nil }
        
        if (ResponseCode.internalErrorMin.rawValue...ResponseCode.internalErrorMax.rawValue).contains(httpResponse.statusCode) {
            return configureError(for: httpResponse, type: .internal)
        } else if criticalErrorCodes.map({ $0.rawValue }).contains(httpResponse.statusCode) {
            return configureError(for: httpResponse, type: .critical)
        } else if !(ResponseCode.successMin.rawValue...ResponseCode.successMax.rawValue).contains(httpResponse.statusCode) {
            return configureError(for: httpResponse, type: .unknown)
        }
        
        return nil
    }
    
    private func configureError(for response: HTTPURLResponse, type: QonversionErrorType, error: Error? = nil, additionalInfo: [String: Any]? = nil) -> QonversionError {
        var info: [String: Any] = [:]
        if let additionalInfo {
            info = additionalInfo
        } else {
            #warning("Don't forget to check the real value and remove this field if the result is useless")
            info[ErrorConstants.messageKey.rawValue] = HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
        }
    
        return QonversionError(type: type, message: type.message(), error: error, additionalInfo: info)
    }
    
}
