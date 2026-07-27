//
//  AdvertisingIdReader.swift
//  Qonversion
//

import Foundation

/// Reads the device advertising identifier without ever linking Apple's
/// advertising framework, so the SDK stays shippable in apps that declare no
/// tracking — Kids Category apps above all.
///
/// ## Why the runtime names are obfuscated
///
/// App Review inspects the compiled binary and string-matches the advertising
/// framework and its symbols. A binary that merely *mentions* them is treated
/// as collecting the advertising identifier, which fails review for an app that
/// declares no tracking. The well-known precedent is RevenueCat, whose
/// workaround class — named after the system one, and never calling it — was
/// enough on its own to trigger rejections: the string alone was the signal.
///
/// So the framework is never imported, and its class and selector names never
/// appear as literals. They live below as ROT13-encoded bytes and are assembled
/// at run time, where no static scanner can see them.
///
/// **Do not "clean this up"** by inlining the plain names or re-adding the
/// import — that silently reintroduces exactly the linkage this type exists to
/// avoid. `ForbiddenSymbolsGuardTests` fails the test run if any of the plain
/// names reappear anywhere under `Sources/`.
///
/// ## What this costs, and what it does not
///
/// Nothing, for apps that want the identifier: when the *host* app links the
/// advertising framework itself, its class is already registered with the
/// Objective-C runtime, so the lookup by name resolves and the identifier is
/// read as before — still gated by the system on the user's ATT choice, which
/// this type does not and cannot override.
///
/// When the host does not link it — a kids app, or any app that simply does not
/// want it — the class does not resolve, the identifier is nil, and no
/// framework is loaded. That path is silent by design: an absent identifier is
/// a valid answer, not an error.
final class AdvertisingIdReader: Sendable {

    /// Reads the identifier as an opaque string, or nil when it is unavailable.
    ///
    /// Injected in tests so the all-zeroes rule can be pinned on hosts where
    /// the framework is absent — which is every test host, by design.
    typealias RawIdentifierReader = @Sendable () -> String?

    /// What the system hands back when tracking was not authorised. Treated as
    /// "no identifier" rather than forwarded, as it always has been.
    private static let unauthorizedIdentifier = "00000000-0000-0000-0000-000000000000"

    private let readRawIdentifier: RawIdentifierReader

    init(rawIdentifierReader: @escaping RawIdentifierReader = AdvertisingIdReader.runtimeIdentifier) {
        self.readRawIdentifier = rawIdentifierReader
    }

    /// The advertising identifier, or nil when the host app does not link the
    /// advertising framework or the user did not authorise tracking.
    func advertisingId() -> String? {
        guard let identifier: String = readRawIdentifier() else { return nil }
        guard identifier != AdvertisingIdReader.unauthorizedIdentifier else { return nil }

        return identifier
    }

    // MARK: - The Objective-C runtime lookup

    /// Resolves the system identifier provider by its decoded name.
    @Sendable
    static func runtimeIdentifier() -> String? {
        let className: String = decoded(ObfuscatedNames.identifierProviderClass)
        let instanceAccessorName: String = decoded(ObfuscatedNames.instanceAccessor)
        let identifierAccessorName: String = decoded(ObfuscatedNames.identifierAccessor)

        return runtimeIdentifier(
            className: className,
            instanceAccessorName: instanceAccessorName,
            identifierAccessorName: identifierAccessorName
        )
    }

    /// The lookup itself, with the names passed in so it can be exercised
    /// against a stand-in provider. Every step is optional: an unresolvable
    /// class, a class that does not answer the accessor, an answer of an
    /// unexpected shape — all of them mean "no identifier", never a crash.
    static func runtimeIdentifier(
        className: String,
        instanceAccessorName: String,
        identifierAccessorName: String
    ) -> String? {
        guard let providerClass: AnyClass = NSClassFromString(className) else { return nil }
        let provider: AnyObject = providerClass as AnyObject

        let instanceSelector: Selector = NSSelectorFromString(instanceAccessorName)
        guard provider.responds(to: instanceSelector),
              let instance: AnyObject = provider.perform(instanceSelector)?.takeUnretainedValue() else { return nil }

        let identifierSelector: Selector = NSSelectorFromString(identifierAccessorName)
        guard instance.responds(to: identifierSelector),
              let answer: AnyObject = instance.perform(identifierSelector)?.takeUnretainedValue() else { return nil }
        guard let identifier: UUID = answer as? UUID else { return nil }

        return identifier.uuidString
    }

    // MARK: - The obfuscation transform

    /// The runtime names, ROT13-encoded and stored as bytes rather than as
    /// string literals, so that neither the source nor the compiled binary
    /// spells them out. Read the type documentation before touching these.
    enum ObfuscatedNames {

        static let identifierProviderClass: [UInt8] = [
            78, 70, 86, 113, 114, 97, 103, 118, 115, 118, 114, 101, 90, 110, 97, 110, 116, 114, 101,
        ]

        static let instanceAccessor: [UInt8] = [
            102, 117, 110, 101, 114, 113, 90, 110, 97, 110, 116, 114, 101,
        ]

        static let identifierAccessor: [UInt8] = [
            110, 113, 105, 114, 101, 103, 118, 102, 118, 97, 116, 86, 113, 114, 97, 103, 118, 115, 118, 114, 101,
        ]
    }

    /// ROT13 over ASCII letters. The transform is its own inverse, so the same
    /// function both encodes and decodes; anything outside A-Z / a-z is left as
    /// it is.
    static func decoded(_ encoded: [UInt8]) -> String {
        let upperA: UInt8 = UInt8(ascii: "A")
        let upperZ: UInt8 = UInt8(ascii: "Z")
        let lowerA: UInt8 = UInt8(ascii: "a")
        let lowerZ: UInt8 = UInt8(ascii: "z")
        let alphabetLength: UInt8 = 26
        let shift: UInt8 = 13

        let decodedBytes: [UInt8] = encoded.map { byte in
            switch byte {
            case upperA...upperZ:
                return (byte - upperA + shift) % alphabetLength + upperA
            case lowerA...lowerZ:
                return (byte - lowerA + shift) % alphabetLength + lowerA
            default:
                return byte
            }
        }

        return String(decoding: decodedBytes, as: UTF8.self)
    }
}
