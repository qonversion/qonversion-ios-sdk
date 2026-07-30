import Foundation

/// Keeps the device identity stable when Apple cannot provide IDFV (or when a
/// Mac has no readable built-in interface). A generated identifier is stored
/// in the host-selected UserDefaults so later launches do not create another
/// backend device.
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

    public func resolve(systemVendorId: String?) -> String {
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

        let generated = uuidProvider().uuidString
        userDefaults.set(generated, forKey: Self.storageKey)
        return generated
    }
}
