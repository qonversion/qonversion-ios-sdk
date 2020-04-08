import XCTest
@testable import Qonversion

class QonversionTests: XCTestCase {
  
  func testThatResult() {
    Qonversion.checkUser({ result in
      guard let activeProduct = result.activeProducts.first else { return }
      switch activeProduct.status {
      case .active:
        print("Test")
      default: break
      }
    }) { error in
      
    }
  }
}
