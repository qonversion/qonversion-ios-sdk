//
//  ExceptionManager.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 08.04.2024.
//

import Foundation

var defaultExceptionHandler: NSUncaughtExceptionHandler?

func uncaughtExceptionHandler(exception: NSException) {
    var isSpm = false
    let isQonversionException = ExceptionManager.shared?.isQonversionException(exception, isSpm: &isSpm)
    if isQonversionException == true {
        ExceptionManager.shared?.storeException(exception, isSpm: isSpm)
    }
    
    if let defaultExceptionHandler = defaultExceptionHandler {
        defaultExceptionHandler(exception)
    }
}

class ExceptionManager : ExceptionManagerInterface {
    
    static var shared: ExceptionManager? = nil
    
    let exceptionService: ExceptionServiceInterface
    let logger: LoggerWrapper
    
    init(exceptionService: ExceptionServiceInterface, logger: LoggerWrapper) {
        self.exceptionService = exceptionService
        self.logger = logger
        
        ExceptionManager.shared = self
        
        defaultExceptionHandler = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler(uncaughtExceptionHandler);
        
        sendCrashReportsInBackground()
    }
    
    func isQonversionException(_ exception: NSException, isSpm: inout Bool) -> Bool {
        exceptionService.isQonversionException(exception, isSpm: &isSpm)
    }
    
    func storeException(_ exception: NSException, isSpm: Bool) {
        exceptionService.storeException(exception, isSpm: isSpm)
    }
    
    private func sendCrashReportsInBackground() {
        Task.init {
            let filenames = exceptionService.getStoredExceptionFilenames()
            for fileURL in filenames {
                if let crashData = exceptionService.loadExceptionData(fileURL.path) {
                    let data: [String: AnyHashable] = [
                        "exception": crashData
                    ]
                    
                    do {
                        try await exceptionService.sendCrashReport(data)
                        exceptionService.removeExceptionFile(fileURL.path)
                    } catch {
                        logger.warning("Error sending crash information to API: \(error)")
                    }
                }
            }
        }
    }
}
