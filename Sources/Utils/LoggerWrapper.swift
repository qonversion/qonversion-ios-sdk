//
//  Logger.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 26.03.2024.
//

import Foundation
import OSLog

enum LoggerInfoMessages: String {
    case deviceCreated = "Device created."
    case deviceUpdated = "Device updated."
    case advertisingIdUnavailable = "Can not collect advertising ID."
    case advertisingIdAlreadyCollected = "Advertising ID already collected."
    case failedToCollectAppleSearchAdsAttribution = "Failed to fetch Apple Search Ads token."
    case unableToCollectAppleSearchAdsAttribution = "Unable to fetch Apple Search Ads token. AdServices available for iOS 14.3 and above."
    case appleSearchAdsAttributionRequestFailed = "Apple Search Ads request failed."
    case appleSearchAdsAttributionRequestSucceeded = "Apple Search Ads request finished successfully."
}

extension Qonversion {

    /// Minimal severity the SDK writes to the unified log.
    public enum LogLevel: Int, Sendable {
        case verbose = 0
        case debug = 1
        case warning = 2
        case error = 3
        case critical = 4
        /// Disables SDK logging entirely.
        case disabled = 5
    }
}

typealias LogLevel = Qonversion.LogLevel

// @unchecked: immutable after init; os.Logger is thread-safe.
final class LoggerWrapper: @unchecked Sendable {
    
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

    /// The SDK's logger with the given severity floor. Used by the assembly
    /// once the SDK is configured, and by the facade before it is — a misuse
    /// warning has to reach the developer even when the misuse is calling
    /// before initialize(), which is exactly when no configured logger exists.
    static func make(logLevel: LogLevel) -> LoggerWrapper {
        if #available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, *) {
            let logger = Logger(subsystem: "io.qonversion.sdk", category: "Internal")

            return LoggerWrapper(logger: logger, logLevel: logLevel)
        }

        return LoggerWrapper()
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
            case .warning:
                osLevel = .default
            case .error:
                osLevel = .error
            case .disabled:
                return
            case .critical:
                osLevel = .fault
            }
            
            logger.log(level: osLevel, "\(message)")
        }
    }
}
