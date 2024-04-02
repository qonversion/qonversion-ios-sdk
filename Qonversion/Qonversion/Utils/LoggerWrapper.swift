//
//  Logger.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 26.03.2024.
//

import Foundation
import OSLog

enum LoggerInfoMessages: String {
    case deviceCreated = "Device created"
    case deviceUpdated = "Device updated"
    case advertisingIdUnavailable = "Can not collect advertising ID"
    case advertisingAlreadyCollected = "Advertising ID already collected"
}

enum LogLevel: Int {
    case critical = 4
    case error = 3
    case warning = 2
    case debug = 1
    case verbose = 0
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
    
    init() {
        self._logger = nil
        self.logLevel = .verbose
    }
    
    func info(_ message: String) {
        log(message, level: .verbose)
    }
    
    func debug(_ message: String) {
        log(message, level: .debug)
    }
    
    func warning(_ message: String) {
        log(message, level: .warning)
    }
    
    func error(_ message: String) {
        log(message, level: .error)
    }
    
    func critical(_ message: String) {
        log(message, level: .critical)
    }
    
}

// MARK: - Private

extension LoggerWrapper {
    
    private func log(_ message: String, level: LogLevel) {
        guard logLevel.rawValue <= level.rawValue else { return }
        
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
                osLevel = .fault
            }
            
            logger.log(level: osLevel, "\(message)")
        }
    }
    
}
