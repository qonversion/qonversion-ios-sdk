//
//  LaunchTests.swift
//  QonversionTests
//
//  Created by Kostya on 16/08/2019.
//

import XCTest
@testable import Qonversion

class LaunchTests: XCTestCase {

    func testIfLaunchWithNilCompletionDoNotFail() {
        let expect = XCTestExpectation(description: "launch")
        
        Qonversion.launch(withKey: "TEST", autoTrackPurchases: true)
        
        // TODO: fullfil expect after timeout
    }

}
