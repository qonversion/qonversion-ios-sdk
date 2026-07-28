//
//  SDKVersion.swift
//  NoCodes
//

import Foundation

/// The No-Codes SDK version sent to the backend in request headers. SPM
/// provides no runtime version metadata, so the version lives in this constant
/// and the release tooling rewrites it.
enum SDKVersion {
    static let current: String = "1.0"
}
