import XCTest
@_spi(QonversionInternal) @testable import Qonversion

final class VendorIdResolverTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = TestDefaults.makeIsolated()
    }

    func testUsesSystemIdentifierWithoutPersistingFallback() {
        let resolver = VendorIdResolver(
            userDefaults: defaults,
            uuidProvider: { UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")! }
        )

        XCTAssertEqual(resolver.resolve(systemVendorId: "system-id"), "system-id")
        XCTAssertNil(defaults.string(forKey: VendorIdResolver.storageKey))
    }

    func testGeneratesAndPersistsFallbackWhenSystemIdentifierIsUnavailable() {
        let resolver = VendorIdResolver(
            userDefaults: defaults,
            uuidProvider: { UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")! }
        )

        let resolved = resolver.resolve(systemVendorId: nil)

        XCTAssertEqual(resolved, "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        XCTAssertEqual(defaults.string(forKey: VendorIdResolver.storageKey), resolved)
    }

    func testStoredFallbackRemainsStableIfSystemIdentifierAppearsLater() {
        defaults.set("persisted-fallback", forKey: VendorIdResolver.storageKey)
        let resolver = VendorIdResolver(userDefaults: defaults)

        XCTAssertEqual(resolver.resolve(systemVendorId: "later-system-id"), "persisted-fallback")
    }

    func testConcurrentResolverInstancesGenerateOnlyOneFallback() {
        let firstProviderStarted = DispatchSemaphore(value: 0)
        let releaseFirstProvider = DispatchSemaphore(value: 0)
        let secondProviderStarted = DispatchSemaphore(value: 0)
        let finished = DispatchGroup()
        let resultsLock = NSLock()
        var results: [String] = []

        let first = VendorIdResolver(
            userDefaults: defaults,
            uuidProvider: {
                firstProviderStarted.signal()
                releaseFirstProvider.wait()
                return UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
            }
        )
        let second = VendorIdResolver(
            userDefaults: defaults,
            uuidProvider: {
                secondProviderStarted.signal()
                return UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
            }
        )

        finished.enter()
        DispatchQueue.global().async {
            let value = first.resolve(systemVendorId: nil)
            resultsLock.withLock { results.append(value) }
            finished.leave()
        }
        XCTAssertEqual(firstProviderStarted.wait(timeout: .now() + 1), .success)

        finished.enter()
        DispatchQueue.global().async {
            let value = second.resolve(systemVendorId: nil)
            resultsLock.withLock { results.append(value) }
            finished.leave()
        }

        let secondEnteredBeforeFirstFinished =
            secondProviderStarted.wait(timeout: .now() + 0.2) == .success
        releaseFirstProvider.signal()
        XCTAssertEqual(finished.wait(timeout: .now() + 2), .success)

        XCTAssertFalse(
            secondEnteredBeforeFirstFinished,
            "separate resolver instances must serialize the read-generate-write transaction"
        )
        XCTAssertEqual(Set(results).count, 1)
    }
}
