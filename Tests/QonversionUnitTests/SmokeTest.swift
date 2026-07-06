import XCTest
@testable import Qonversion

final class SmokeTest: XCTestCase {
    func testModuleLinks() {
        XCTAssertEqual(InternalConfig(userId: "u").getUserId(), "u")
    }
}
