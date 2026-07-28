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

    /// The sdk-logs payload, in the ObjC SDK's key layout — that service has
    /// received this exact shape for years and is the only consumer.
    /// `sdk_version` and `occurred_at` are ours and ride inside the crash
    /// payload, which the service stores as it arrives.
    func requestBody(device: SdkLogDevice) -> RequestBodyDict {
        let exception: RequestBodyDict = [
            "rawStackTrace": stackTrace.joined(separator: "\n"),
            "elements": stackTrace as RequestBodyArray,
            "name": name,
            "message": reason,
            "isSpm": linkage == .spm,
            "title": name + ": " + reason,
            "userInfo": RequestBodyDict(),
            "sdk_version": sdkVersion,
            "occurred_at": Int(occurredAt.timeIntervalSince1970)
        ]

        return [
            "device": device.requestBodyValue,
            "exception": exception
        ]
    }
}

/// The envelope every sdk-logs payload carries. Its keys are fixed by the
/// service, not by this SDK.
struct SdkLogDevice: Equatable, Sendable {

    private enum SourceOverrideKeys: String {
        case source = "com.qonversion.keys.source"
        case sourceVersion = "com.qonversion.keys.sourceVersion"
    }

    let platform: String
    let platformVersion: String
    let source: String
    let sourceVersion: String
    let projectKey: String
    let uid: String

    /// Resolves the source the same way the request headers do — the sdk-logs
    /// service reads the two the same way, so they must not disagree. A version
    /// override without a source override is a leftover the Objective-C SDK
    /// wrote, not a cross-platform wrapper. `uid` is filled in by the sender,
    /// once the user gate has run.
    static func make(deviceInfo: HeaderDeviceInfo, projectKey: String, sdkVersion: String, userDefaults: UserDefaults) -> SdkLogDevice {
        let sourceOverride: String? = userDefaults.string(forKey: SourceOverrideKeys.source.rawValue)
        let versionOverride: String? = userDefaults.string(forKey: SourceOverrideKeys.sourceVersion.rawValue)

        return SdkLogDevice(
            platform: deviceInfo.osName,
            platformVersion: deviceInfo.osVersion,
            source: sourceOverride ?? "iOS",
            sourceVersion: sourceOverride == nil ? sdkVersion : (versionOverride ?? sdkVersion),
            projectKey: projectKey,
            uid: ""
        )
    }

    func withUid(_ uid: String) -> SdkLogDevice {
        return SdkLogDevice(
            platform: platform,
            platformVersion: platformVersion,
            source: source,
            sourceVersion: sourceVersion,
            projectKey: projectKey,
            uid: uid
        )
    }

    var requestBodyValue: RequestBodyDict {
        return [
            "platform": platform,
            "platform_version": platformVersion,
            "source": source,
            "source_version": sourceVersion,
            "project_key": projectKey,
            "uid": uid
        ]
    }
}
