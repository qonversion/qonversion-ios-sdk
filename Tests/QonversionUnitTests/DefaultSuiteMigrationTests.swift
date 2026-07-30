import XCTest
@testable import Qonversion

final class DefaultSuiteMigrationTests: XCTestCase {

    private var source: UserDefaults!
    private var destination: UserDefaults!

    override func setUp() {
        super.setUp()
        source = TestDefaults.makeIsolated("migration-source")
        destination = TestDefaults.makeIsolated("migration-destination")
    }

    func testMigrationMovesOnlyAllowlistedKeys() {
        source.set("owned-value", forKey: "owned")
        source.set("host-value", forKey: "host")

        DefaultSuiteMigration(
            source: source,
            destination: destination
        ).move(keys: ["owned"])

        XCTAssertEqual(destination.string(forKey: "owned"), "owned-value")
        XCTAssertNil(source.object(forKey: "owned"))
        XCTAssertNil(destination.object(forKey: "host"))
        XCTAssertEqual(source.string(forKey: "host"), "host-value")
    }

    func testExistingDestinationValueWinsAndTheStaleSourceIsConsumed() {
        source.set("stale", forKey: "owned")
        destination.set("current", forKey: "owned")

        DefaultSuiteMigration(
            source: source,
            destination: destination
        ).move(keys: ["owned"])

        XCTAssertEqual(destination.string(forKey: "owned"), "current")
        XCTAssertNil(source.object(forKey: "owned"))
    }

    func testRunningMigrationTwiceIsHarmless() {
        source.set(["first", "second"], forKey: "owned")
        let migration = DefaultSuiteMigration(
            source: source,
            destination: destination
        )

        migration.move(keys: ["owned"])
        migration.move(keys: ["owned"])

        XCTAssertEqual(destination.stringArray(forKey: "owned"), ["first", "second"])
        XCTAssertNil(source.object(forKey: "owned"))
    }

    func testSourceOverrideSyncUsesTheLatestSourceValueWithoutConsumingIt() {
        destination.set("old", forKey: "source")
        source.set("new", forKey: "source")
        let migration = DefaultSuiteMigration(
            source: source,
            destination: destination
        )

        migration.synchronize(keys: ["source"])

        XCTAssertEqual(destination.string(forKey: "source"), "new")
        XCTAssertEqual(source.string(forKey: "source"), "new")
    }

    func testSourceOverrideSyncRemovesAStaleDestinationValueWhenSourceWasCleared() {
        destination.set("stale", forKey: "sourceVersion")
        let migration = DefaultSuiteMigration(
            source: source,
            destination: destination
        )

        migration.synchronize(keys: ["sourceVersion"])

        XCTAssertNil(destination.object(forKey: "sourceVersion"))
    }
}
