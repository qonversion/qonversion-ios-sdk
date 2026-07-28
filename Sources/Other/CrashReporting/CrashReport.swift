//
//  CrashReport.swift
//  Qonversion
//

import Foundation

/// One uncaught NSException whose stack ran through the SDK.
///
/// `linkage` rides the wire because it decides how the stack symbolicates:
/// `framework` when the SDK is its own image, `spm` when it is linked into the
/// host executable.
struct CrashReport: Codable, Equatable {

    /// Keys removal after a send, and separates two reports of one exception.
    let id: String
    let name: String
    let reason: String
    let stackTrace: [String]
    let linkage: Linkage
    let occurredAt: Date
    let sdkVersion: String

    /// Local bookkeeping, not part of the wire contract.
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

    /// Hand-written only for `sendAttempts`: synthesized decoding throws on the
    /// key missing from pre-upgrade reports, dropping the whole stored queue.
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
