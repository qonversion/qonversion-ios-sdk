//
//  ExceptionManagerInterface.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 08.04.2024.
//

import Foundation

protocol ExceptionManagerInterface {
    func isQonversionException(_ exception: NSException, isSpm: inout Bool) -> Bool

    func storeException(_ exception: NSException, isSpm: Bool)
}
