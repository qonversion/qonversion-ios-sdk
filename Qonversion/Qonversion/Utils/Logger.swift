//
//  Logger.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 26.03.2024.
//

import Foundation
import OSLog

enum LogLevel {
    case critical
    case error
    case warning
    case debug
    case verbose
}

final class LoggerWrapper {
    
    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
    var logger: Logger? { _logger as? Logger }
    let _logger: Any?
    
    let logLevel: LogLevel
    
    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
    init(logger: Logger?, logLevel: LogLevel) {
        self._logger = logger
        self.logLevel = logLevel
    }
    
    func info(_ message: String) {
        guard logLevel == .verbose else { return }
        
        log(message, level: .verbose)
    }
    
    func debug(_ message: String) {
        guard logLevel == .verbose || logLevel == .debug else { return }
        
        log(message, level: .debug)
    }
    
    func warning(_ message: String) {
        guard logLevel == .verbose || logLevel == .debug || logLevel == .warning else { return }
        
        log(message, level: .warning)
    }
    
    func error(_ message: String) {
        guard logLevel == .verbose || logLevel == .debug || logLevel == .warning || logLevel == .error else { return }
        
        log(message, level: .error)
    }
    
    func critical(_ message: String) {
        guard logLevel == .critical else { return }
        
        log(message, level: .critical)
    }
    
    func log(_ message: String, level: LogLevel) {
        if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *), let logger {
            var osLevel: OSLogType = .info
            switch level {
            case .verbose:
                osLevel = .info
            case .debug:
                osLevel = .debug
            case .warning, .error:
                osLevel = .error
            case .critical:
                osLevel = .info
            }
            
            logger.log(level: osLevel, "\(message)")
        }
    }
    
}
