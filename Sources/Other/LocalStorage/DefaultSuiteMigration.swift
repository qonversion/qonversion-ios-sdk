import Foundation

/// Moves the SDK's allowlisted values out of the host application's standard
/// defaults and keeps externally-authored compatibility values synchronized.
///
/// One process-wide lock covers main SDK and NoCodes calls through
/// `QonversionDefaults`, so concurrent initialization cannot interleave a
/// destination check with another migration.
final class DefaultSuiteMigration {

    private static let lock = NSLock()

    private let source: UserDefaults
    private let destination: UserDefaults

    init(source: UserDefaults, destination: UserDefaults) {
        self.source = source
        self.destination = destination
    }

    func move(keys: [String]) {
        Self.lock.withLock {
            for key in Set(keys) {
                guard let sourceValue = source.object(forKey: key) else {
                    continue
                }

                if destination.object(forKey: key) == nil {
                    destination.set(sourceValue, forKey: key)
                }
                source.removeObject(forKey: key)
            }
        }
    }

    func synchronize(keys: [String]) {
        Self.lock.withLock {
            for key in Set(keys) {
                if let sourceValue = source.object(forKey: key) {
                    destination.set(sourceValue, forKey: key)
                } else {
                    destination.removeObject(forKey: key)
                }
            }
        }
    }
}
