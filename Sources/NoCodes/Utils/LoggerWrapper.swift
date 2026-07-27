//
//  Logger.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 26.03.2024.
//

import Foundation
import OSLog

enum LoggerInfoMessages: String {
  case productsLoadingFailed = "Failed to load the products"
  case screenLoadingFailed = "Failed to load the screen"
  case deeplingHandlingFailed = "Failed to handle the deeplink"
  case urlHandlingFailed = "Failed to handle the URL"
  case screenEventTrackingFailed = "Failed to send screen events"
  case screenEventFlushed = "Screen events flushed successfully"
}

enum LogLevel: Int {
    case critical = 4
    case error = 3
    case warning = 2
    case debug = 1
    case verbose = 0
}

// os.Logger is available on every platform this package supports, so the
// wrapper stores it directly instead of the old Any-based back deployment.
final class LoggerWrapper: Sendable {

    let logger: Logger?

    let logLevel: LogLevel

    init(logger: Logger?, logLevel: LogLevel) {
        self.logger = logger
        self.logLevel = logLevel
    }

    init() {
        self.logger = nil
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
        guard logLevel.rawValue <= level.rawValue, let logger else { return }

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
