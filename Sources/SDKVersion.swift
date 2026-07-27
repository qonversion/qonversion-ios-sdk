//
//  SDKVersion.swift
//  Qonversion
//

import Foundation

/// The SDK version sent to the backend in request headers.
/// SPM provides no runtime version metadata, so the version lives in this
/// constant; the release tooling (fastlane bump) rewrites it on every release.
enum SDKVersion {
    static let current: String = "1.0"
}
