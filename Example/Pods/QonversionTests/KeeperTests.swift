import XCTest
@testable import Qonversion

fileprivate enum Constants {
    static let userID = "Borat1950"
}

class KeeperTests: XCTestCase {
    private let keeper = Keeper.self
    private let stubUserID = Constants.userID
    
    func testIfKeeperSetNReadSameUserID() {
        keeper.setUserID(stubUserID)
        guard let keepedUserID = keeper.userID() else {
            XCTAssert(false, "keepedUserID is nil")
            return
        }
        
        XCTAssert(keepedUserID == stubUserID,
                  "keepedUserID(\(keepedUserID)) != stubUserID(\(stubUserID))")
    }
    
    override func tearDown() {
        keeper.setUserID("")
    }
}
