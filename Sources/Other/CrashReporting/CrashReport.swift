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

    /// How many times the backend answered and still did not take this report.
    /// Local bookkeeping only — it is not part of the wire contract; see
    /// ``CrashReportsSender/maxSendAttempts`` for what it bounds.
    let sendAttempts: Int

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
        sdkVersion: String = SDKVersion.current,
        sendAttempts: Int = 0
    ) {
        self.id = id
        self.name = name
        self.reason = reason
        self.stackTrace = stackTrace
        self.linkage = linkage
        self.occurredAt = occurredAt
        self.sdkVersion = sdkVersion
        self.sendAttempts = sendAttempts
    }

    /// A report stored by a build that predates the attempt counter carries no
    /// `sendAttempts` key. Synthesized decoding does NOT fall back to the
    /// memberwise default for a missing non-optional field — it throws, and a
    /// throw here would drop the WHOLE stored queue on the first launch after
    /// the upgrade, which is exactly the crash evidence an upgrade needs most.
    init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.reason = try container.decode(String.self, forKey: .reason)
        self.stackTrace = try container.decode([String].self, forKey: .stackTrace)
        self.linkage = try container.decode(Linkage.self, forKey: .linkage)
        self.occurredAt = try container.decode(Date.self, forKey: .occurredAt)
        self.sdkVersion = try container.decode(String.self, forKey: .sdkVersion)
        self.sendAttempts = try container.decodeIfPresent(Int.self, forKey: .sendAttempts) ?? 0
    }

    /// The same report, one answered-but-not-taken send later.
    func countingSendAttempt() -> CrashReport {
        return CrashReport(
            id: id,
            name: name,
            reason: reason,
            stackTrace: stackTrace,
            linkage: linkage,
            occurredAt: occurredAt,
            sdkVersion: sdkVersion,
            sendAttempts: sendAttempts + 1
        )
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
