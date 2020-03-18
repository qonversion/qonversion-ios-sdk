import XCTest
@testable import Qonversion

fileprivate enum Constants {
    static let timeoutSeconds = 6
}

class LaunchTests: XCTestCase {
    func testIfLaunchWithNilCompletionDoNotFail() {
        let timeoutSeconds = Constants.timeoutSeconds
        let timeoutInterval = DispatchTimeInterval.seconds(timeoutSeconds)
        let launchExpect = XCTestExpectation(description: "launch")
        
        Qonversion.launch(withKey: "TEST", autoTrackPurchases: true)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutInterval) {
            launchExpect.fulfill()
        }
        
        wait(for: [launchExpect], timeout: TimeInterval(timeoutSeconds + 1))
    }
}
