import Foundation

/// Keeps the device identity stable on the platforms that offer no vendor
/// identifier at all (a Mac with no readable built-in interface). A generated
/// identifier is stored in the host-selected UserDefaults so later launches do
/// not create another backend device.
@_spi(QonversionInternal)
public final class VendorIdResolver: @unchecked Sendable {

    public static let storageKey = "io.qonversion.sdk.storage.fallbackVendorId"

    public typealias UUIDProvider = @Sendable () -> UUID

    private let userDefaults: UserDefaults
    private let uuidProvider: UUIDProvider
    private static let lock = NSLock()

    public init(
        userDefaults: UserDefaults,
        uuidProvider: @escaping UUIDProvider = { UUID() }
    ) {
        self.userDefaults = userDefaults
        self.uuidProvider = uuidProvider
    }

    /// - Parameter systemIdentityIsFinal: whether a missing system identifier
    ///   means the platform has none at all. Pass false wherever it can appear
    ///   later — IDFV is nil until the first unlock after a reboot, and a
    ///   background launch before that must not latch a substitute for it.
    public func resolve(systemVendorId: String?, systemIdentityIsFinal: Bool) -> String? {
        Self.lock.lock()
        defer { Self.lock.unlock() }

        // Once a fallback has been issued, it remains authoritative. Switching
        // to an IDFV that appears later would create a second device row.
        if let stored = userDefaults.string(forKey: Self.storageKey),
           !stored.isEmpty {
            return stored
        }

        if let systemVendorId, !systemVendorId.isEmpty {
            return systemVendorId
        }

        guard systemIdentityIsFinal else { return nil }

        let generated = uuidProvider().uuidString
        userDefaults.set(generated, forKey: Self.storageKey)
        return generated
    }
}
