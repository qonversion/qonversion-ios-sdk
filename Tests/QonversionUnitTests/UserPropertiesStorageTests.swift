//
//  UserPropertiesStorageTests.swift
//  QonversionUnitTests
//
//  Fixation tests for UserPropertiesStorage: locks in current behavior as-is.
//

import XCTest
@testable import Qonversion

final class UserPropertiesStorageConcurrencyTests: XCTestCase {

    func testConcurrentSavesAndReadsDoNotLoseProperties() async {
        let storage = UserPropertiesStorage()

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<200 {
                group.addTask {
                    storage.save(Qonversion.UserProperty(key: "key_\(index)", value: "value"))
                }
                group.addTask {
                    _ = storage.all()
                }
            }
        }

        XCTAssertEqual(storage.all().count, 200)
    }

    func testConcurrentSaveAndClearDoNotCrash() async {
        let storage = UserPropertiesStorage()
        let seed = (0..<50).map { Qonversion.UserProperty(key: "seed_\($0)", value: "v") }
        seed.forEach { storage.save($0) }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { storage.clear(properties: seed) }
            for index in 0..<100 {
                group.addTask {
                    storage.save(Qonversion.UserProperty(key: "new_\(index)", value: "v"))
                }
            }
        }

        XCTAssertEqual(storage.all().count, 100, "the cleared seed must not swallow concurrent saves")
    }
}

final class UserPropertiesStorageTests: XCTestCase {

    func testNewInstanceStartsEmpty() {
        // Fixates current behavior: the storage is in-memory only, so every
        // new instance starts empty — nothing survives a restart.
        let storage = UserPropertiesStorage()

        XCTAssertTrue(storage.all().isEmpty)
    }

    func testSaveAppendsPropertiesInOrder() {
        let storage = UserPropertiesStorage()
        let first = Qonversion.UserProperty(key: "_q_email", value: "dev@qonversion.io")
        let second = Qonversion.UserProperty(key: "custom_key", value: "custom_value")

        storage.save(first)
        storage.save(second)

        XCTAssertEqual(storage.all(), [first, second])
    }

    func testSaveAppendsDuplicateKeysInsteadOfReplacing() {
        let storage = UserPropertiesStorage()
        let first = Qonversion.UserProperty(key: "same_key", value: "value_1")
        let second = Qonversion.UserProperty(key: "same_key", value: "value_2")

        storage.save(first)
        storage.save(second)

        // Fixates current behavior: save() appends; duplicate keys are NOT deduplicated.
        XCTAssertEqual(storage.all(), [first, second])
    }

    func testSaveAppendsIdenticalPropertyTwice() {
        let storage = UserPropertiesStorage()
        let property = Qonversion.UserProperty(key: "key", value: "value")

        storage.save(property)
        storage.save(property)

        // Fixates current behavior: identical properties are stored twice.
        XCTAssertEqual(storage.all(), [property, property])
    }

    func testClearPropertiesRemovesOnlyMatchingProperties() {
        let storage = UserPropertiesStorage()
        let toRemove = Qonversion.UserProperty(key: "remove_me", value: "1")
        let toKeep = Qonversion.UserProperty(key: "keep_me", value: "2")
        storage.save(toRemove)
        storage.save(toKeep)

        storage.clear(properties: [toRemove])

        XCTAssertEqual(storage.all(), [toKeep])
    }

    func testClearPropertiesRemovesAllDuplicatesOfMatchingProperty() {
        let storage = UserPropertiesStorage()
        let property = Qonversion.UserProperty(key: "key", value: "value")
        storage.save(property)
        storage.save(property)

        storage.clear(properties: [property])

        // Fixates current behavior: clear(properties:) removes ALL occurrences,
        // even if the property was saved multiple times but cleared once.
        XCTAssertTrue(storage.all().isEmpty)
    }

    func testClearPropertiesDoesNotRemovePropertyWithSameKeyButDifferentValue() {
        let storage = UserPropertiesStorage()
        let saved = Qonversion.UserProperty(key: "key", value: "actual")
        storage.save(saved)

        storage.clear(properties: [Qonversion.UserProperty(key: "key", value: "different")])

        // Matching is by full equality (key AND value), not by key.
        XCTAssertEqual(storage.all(), [saved])
    }

    func testClearRemovesEverything() {
        let storage = UserPropertiesStorage()
        storage.save(Qonversion.UserProperty(key: "a", value: "1"))
        storage.save(Qonversion.UserProperty(key: "b", value: "2"))

        storage.clear()

        XCTAssertTrue(storage.all().isEmpty)
    }

    func testAllReturnsCopyReflectingCurrentState() {
        let storage = UserPropertiesStorage()
        let property = Qonversion.UserProperty(key: "a", value: "1")
        storage.save(property)

        let snapshot = storage.all()
        storage.clear()

        // The previously returned array is a value-type copy and is unaffected.
        XCTAssertEqual(snapshot, [property])
        XCTAssertTrue(storage.all().isEmpty)
    }
}
