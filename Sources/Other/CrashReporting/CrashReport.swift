//
//  CrashReport.swift
//  Qonversion
//

import Foundation

/// One uncaught NSException whose stack ran through the SDK.
///
/// Proposed wire contract for `POST v4/sdk-crashes` (the endpoint does not
/// exist yet — see ``CrashReporter``):
///
/// ```json
/// {
///   "sdk_version": "6.0.0",
///   "platform": "ios",
///   "occurred_at": 1700000000,
///   "user_id": "QON_...",
///   "exception": {
///     "name": "NSInvalidArgumentException",
///     "reason": "-[NSNull length]: unrecognized selector sent to instance",
///     "linkage": "spm",
///     "stack_trace": [
///       "0   Qonversion   0x00000001 $s10Qonversion... + 42",
///       "1   MyApp        0x00000002 main + 12"
///     ]
///   }
/// }
/// ```
///
/// `linkage` distinguishes the two ways the SDK ends up in the binary, because
/// it changes how the stack is symbolicated: `"framework"` when the SDK is its
/// own image (the frame's image name is `Qonversion`) and `"spm"` when it is
/// statically linked into the host executable.
struct CrashReport: Codable, Equatable {

    /// Distinguishes two reports of the same exception, and keys removal after
    /// a successful send.
    let id: String
    let name: String
    let reason: String
    let stackTrace: [String]
    let linkage: Linkage
    let occurredAt: Date
    let sdkVersion: String

    enum Linkage: String, Codable {
        /// The SDK is its own binary image.
        case framework
        /// The SDK is statically linked into the host executable.
        case spm
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        reason: String,
        stackTrace: [String],
        linkage: Linkage,
        occurredAt: Date = Date(),
        sdkVersion: String = SDKVersion.current
    ) {
        self.id = id
        self.name = name
        self.reason = reason
        self.stackTrace = stackTrace
        self.linkage = linkage
        self.occurredAt = occurredAt
        self.sdkVersion = sdkVersion
    }

    /// The ObjC SDK defaulted a missing reason to this exact string.
    static var unknownReason: String { "Unknown reason" }

    func requestBody(userId: String, platform: String) -> RequestBodyDict {
        let exception: RequestBodyDict = [
            "name": name,
            "reason": reason,
            "linkage": linkage.rawValue,
            "stack_trace": stackTrace as RequestBodyArray
        ]

        return [
            "sdk_version": sdkVersion,
            "platform": platform,
            "occurred_at": Int(occurredAt.timeIntervalSince1970),
            "user_id": userId,
            "exception": exception
        ]
    }
}
