//
//  ExceptionService.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 05.04.2024.
//

import Foundation

fileprivate enum Constants: String {
    case crashLogFileSuffix = ".qonversion.stacktrace"
    case defaultExceptionReason = "Unknown reason"
    case stackTraceLinePartsPattern = "\\S+\\s+(\\S+)"
    case sdkBinaryName = "Qonversion"
}

final class ExceptionService : ExceptionServiceInterface {

    private let requestProcessor: RequestProcessorInterface
    private let localStorage: LocalStorage
    private let logger: LoggerWrapper
    
    init(requestProcessor: RequestProcessorInterface, localStorage: LocalStorage, logger: LoggerWrapper) {
        self.requestProcessor = requestProcessor
        self.localStorage = localStorage
        self.logger = logger
    }

    func storeException(_ exception: NSException, isSpm: Bool) {
        let backtrace = exception.callStackSymbols
        let rawStackTrace = backtrace.joined(separator: "\n")
        let reason = exception.reason ?? Constants.defaultExceptionReason.rawValue
        let name = exception.name
        let userInfo = exception.userInfo ?? [:]

        var crashInfo = [String: Any]()

        crashInfo["rawStackTrace"] = rawStackTrace
        crashInfo["elements"] = backtrace
        crashInfo["name"] = name
        crashInfo["message"] = reason
        crashInfo["isSpm"] = isSpm
        crashInfo["title"] = "\(name): \(reason)"
        crashInfo["userInfo"] = userInfo

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: crashInfo, options: [])
            let jsonString = String(data: jsonData, encoding: .utf8)

            let uuidString = UUID().uuidString
            let timeInterval = Date().timeIntervalSince1970
            let filename = "\(uuidString)-\(timeInterval)\(Constants.crashLogFileSuffix.rawValue)"
            if let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let filePath = documentsDirectory.appendingPathComponent(filename)
                do {
                    try jsonString?.write(to: filePath, atomically: true, encoding: .utf8)
                } catch {
                    logger.warning("Failed to save crash information: \(error)")
                }
            } else {
                logger.warning("Failed to find file path to save crash information: \(filename)")
            }
        } catch {
            logger.warning("Failed to convert crash information to JSON: \(error)")
        }
    }

    func getStoredExceptionFilenames() -> Array<URL> {
        guard let directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("Failed to find documents directory with crash information files")
            return []
        }

        do {
            let foundFileURLs = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [URLResourceKey.nameKey, URLResourceKey.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            ).filter { $0.lastPathComponent.hasSuffix(Constants.crashLogFileSuffix.rawValue) }

            return foundFileURLs
        } catch {
            print("Failed to retrieve crash information files: \(error)")
            return []
        }

    }
    
    func loadExceptionData(_ filename: String) -> Dictionary<String, AnyHashable>? {
        do {
            let crashInfoJson = try String(contentsOfFile: filename, encoding: .utf8)
            guard let jsonData = crashInfoJson.data(using: .utf8) else {
                logger.warning("Failed to read data from crash report. Filename: \(filename)")
                return nil
            }
            let dictionary = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: AnyHashable]
            return dictionary
        } catch {
            logger.warning("Failed to read data from crash report: \(error). Filename: \(filename)")
            return nil
        }
    }
    
    func removeExceptionFile(_ filename: String) {
        if FileManager.default.fileExists(atPath: filename) {
            do {
                try FileManager.default.removeItem(atPath: filename)
            } catch {
                logger.warning("Failed to remove crash report file: \(error). Filename: \(filename)")
            }
        } else {
            logger.warning("Crash report file not found at path: \(filename)")
        }
    }
    
    func sendCrashReport(_ data: Dictionary<String, AnyHashable>) async throws {
        let request = Request.sendCrashLogs(body: data)
        do {
            try await requestProcessor.process(request: request, responseType: EmptyApiResponse.self)
        } catch {
            throw QonversionError(type: QonversionErrorType.crashLogSendingFailed, message: nil, error: error)
        }
    }
    
    func isQonversionException(_ exception: NSException, isSpm: inout Bool) -> Bool {
        let appName = Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String
        let regex = try? NSRegularExpression(pattern: Constants.stackTraceLinePartsPattern.rawValue, options: [])
        
        let callStackSymbols = exception.callStackSymbols
        for callStackSymbol in callStackSymbols {
            if let result = regex?.firstMatch(in: callStackSymbol, options: [], range: NSRange(location: 0, length: callStackSymbol.count)) {
                if result.numberOfRanges > 1 {
                    let binaryName = (callStackSymbol as NSString).substring(with: result.range(at: 1))
                    
                    if binaryName == Constants.sdkBinaryName.rawValue {
                        isSpm = false
                        return true
                    }
                    if binaryName == appName {
                        let kQonversionClassPrefixes = ["Qonversion", "QON", "QN"]
                        for prefix in kQonversionClassPrefixes {
                            let entry = "-[\(prefix)"
                            if let range = callStackSymbol.range(of: entry) {
                                isSpm = true
                                return true
                            }
                        }
                        return false
                    }
                }
            }
        }
        
        return false
    }
}
