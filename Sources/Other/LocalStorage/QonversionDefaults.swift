import Foundation

/// Shared persistence selection for the main SDK and the NoCodes module.
///
/// SPI keeps the public SDK surface small while allowing the NoCodes target,
/// which depends on Qonversion, to use exactly the same default domain.
@_spi(QonversionInternal)
public enum QonversionDefaults {

    /// Per-app on purpose. A non-sandboxed macOS process maps a suite to a file
    /// in the user's own preferences folder, so a fixed name would be one store
    /// shared by every Qonversion app the user has installed.
    public static var suiteName: String { suiteNamePrefix + (Bundle.main.bundleIdentifier ?? "default") }

    private static let suiteNamePrefix = "io.qonversion.sdk."
    public static let sourceOverrideKeys = [
        "com.qonversion.keys.source",
        "com.qonversion.keys.sourceVersion"
    ]

    public static func resolve(_ customDefaults: UserDefaults?) -> UserDefaults {
        if let customDefaults {
            return customDefaults
        }

        // A fixed, valid suite name is expected to be constructible on every
        // supported Foundation platform. Falling back to .standard would
        // silently split main SDK and NoCodes state, so fail loudly instead.
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create Qonversion UserDefaults suite")
        }

        return defaults
    }

    public static func moveStandardValues(
        to destination: UserDefaults,
        keys: [String]
    ) {
        DefaultSuiteMigration(
            source: .standard,
            destination: destination
        ).move(keys: keys)
    }

    public static func synchronizeStandardValues(
        to destination: UserDefaults,
        keys: [String]
    ) {
        DefaultSuiteMigration(
            source: .standard,
            destination: destination
        ).synchronize(keys: keys)
    }
}
