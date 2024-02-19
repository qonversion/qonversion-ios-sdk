//
//  NetworkErrorHandler.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 07.02.2024.
//

class NetworkErrorHandler: NetworkErrorHandlerInterface {
    
    let criticalErrorCodes: [ErrorCodes]
    
    init(criticalErrorCodes: [ErrorCodes]) {
        self.criticalErrorCodes = criticalErrorCodes
    }
    
    func extractError(from response: URLResponse) -> QonversionError? {
        guard let httpResponse = response as? HTTPURLResponse else { return nil }
        
        if (ErrorCodes.internalErrorStart.rawValue...ErrorCodes.internalErrorEnd.rawValue).contains(httpResponse.statusCode) {
            let additinalInfo: [String: String] = ["message": HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)]
            let errorType: QonversionErrorType = .internal
            
            return QonversionError(type: errorType, message: errorType.message(), error: nil, additionalInfo: additinalInfo)
        } else if criticalErrorCodes.map({ $0.rawValue }).contains(httpResponse.statusCode) {
            let additinalInfo: [String: String] = ["message": HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)]
            let errorType: QonversionErrorType = .critical
            
            return QonversionError(type: errorType, message: errorType.message(), error: nil, additionalInfo: additinalInfo)
        }
        
        return nil
    }
    
}
