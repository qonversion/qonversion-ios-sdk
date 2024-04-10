//
//  ExceptionServiceInterface.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 05.04.2024.
//

import Foundation

protocol ExceptionServiceInterface {
    
    func storeException(_ exception: NSException, isSpm: Bool)
    
    func getStoredExceptionFilenames() -> Array<URL>
    
    func loadExceptionData(_ filename: String) -> Dictionary<String, AnyHashable>?
    
    func removeExceptionFile(_ filename: String)
    
    func sendCrashReport(_ data: Dictionary<String, AnyHashable>) async throws
    
    func isQonversionException(_ exception: NSException, isSpm: inout Bool) -> Bool
}
