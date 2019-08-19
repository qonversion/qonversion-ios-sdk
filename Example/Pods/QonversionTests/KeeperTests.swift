//
//  KeeperTests.swift
//  QonversionTests
//
//  Created by Kostya on 16/08/2019.
//

import XCTest
@testable import Qonversion

fileprivate enum Constants {
    static let userID = "Borat1950"
    static let initialIP = "127.0.0.1"
}

class KeeperTests: XCTestCase {
    private let keeper = Keeper.self
    private let stubUserID = Constants.userID
    private let stubInitialIP = Constants.initialIP
    
    func testIfKeeperSetNReadSameUserID() {
        keeper.setUserID(stubUserID)
        guard let keepedUserID = keeper.userID() else {
            XCTAssert(false, "keepedUserID is nil")
            return
        }
        
        XCTAssert(keepedUserID == stubUserID,
                  "keepedUserID(\(keepedUserID)) != stubUserID(\(stubUserID))")
    }
    
    func testIfKeeperSetNReadSameInitialIP() {
        keeper.setInitialIP(stubInitialIP)
        guard let keepedInitialIP = keeper.initialIP() else {
            XCTAssert(false, "")
            return
        }
        
        XCTAssert(keepedInitialIP == stubInitialIP,
                  "keepedInitialIP(\(keepedInitialIP)) != stubInitialIP(\(stubInitialIP))")
    }
    
    override func tearDown() {
        keeper.setUserID("")
        keeper.setInitialIP("")
    }
}
