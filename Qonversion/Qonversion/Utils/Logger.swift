//
//  Logger.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 26.03.2024.
//

import Foundation
import OSLog

enum LogLevel {
    // Use this level to capture information that may be useful during development or while troubleshooting a specific problem.
    case debug
    
    // Use this level to capture information that may be helpful, but not essential, for troubleshooting errors.
    case info
    
    // Use this level to capture information about things that might result in a failure.
    case `default`
    
    // Use this log level to report process-level errors.
    case error
    
    // Use this level only to capture system-level or multiprocess information when reporting system errors.
    case fault
}

final class LoggerWrapper {
    
    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
    var logger: Logger? { _logger as? Logger }
    let _logger: Any?
    
    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
    init(logger: Logger?) {
        self._logger = logger
    }
    
    func debug(_ message: String) {
        if #available(iOS 14.0, *) {
            logger?.debug(<#T##message: OSLogMessage##OSLogMessage#>)
        }
    }
    
    func info(_ message: String) {
        if #available(iOS 14.0, *) {
            logger?.info(OSLogMessage)
        }
    }
    
    func log(_ message: String) {
        if #available(iOS 14.0, *) {
            logger?.log(<#T##message: OSLogMessage##OSLogMessage#>)
        }
    }
    
    func error(_ message: String) {
        if #available(iOS 14.0, *) {
            logger?.error(<#T##message: OSLogMessage##OSLogMessage#>)
        }
    }
    
    func fault(_ message: String) {
        if #available(iOS 14.0, *) {
            logger?.fault(<#T##message: OSLogMessage##OSLogMessage#>)
        }
    }
    
}
