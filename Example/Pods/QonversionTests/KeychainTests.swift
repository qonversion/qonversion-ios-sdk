//
//  KeychainTests.swift
//  QonversionTests
//
//  Created by Kostya on 16/08/2019.
//

import XCTest
@testable import Qonversion

fileprivate enum Constants {
    static let stubKey = "StubKey"
    static let stubVal = "StubVal"
}

class KeychainTests: XCTestCase {
    let keychain = Keychain.self
    let originalThing = (key: Constants.stubKey,
                         val: Constants.stubVal)

    override func tearDown() {
        if keychain.string(forKey: originalThing.key) != nil {
            keychain.setString("", forKey: originalThing.key)
        }
    }

    func testKeychainWritesAndReadsSameThing() {
        keychain.setString(originalThing.val, forKey: originalThing.key)
        let storedThingVal = keychain.string(forKey: originalThing.key)
        
        XCTAssert(originalThing.val == storedThingVal,
                  "testKeychainWritesAndReadsSameThing: originalThingVal(\(originalThing.val)) not equal storedThingVal(\(String(describing: storedThingVal)))")
    }
}
