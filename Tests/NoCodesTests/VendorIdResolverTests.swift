import XCTest
@_spi(QonversionInternal) import Qonversion
@testable import NoCodes

final class VendorIdResolverTests: XCTestCase {

    func testFallbackIsStableAcrossCollectorLifetimes() {
        let defaults = TestDefaults.makeIsolated()
        let first = VendorIdResolver(
            userDefaults: defaults,
            uuidProvider: { UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")! }
        )

        let generated = first.resolve(systemVendorId: nil)
        let second = VendorIdResolver(
            userDefaults: defaults,
            uuidProvider: { UUID(uuidString: "11111111-2222-3333-4444-555555555555")! }
        )

        XCTAssertEqual(generated, "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        XCTAssertEqual(second.resolve(systemVendorId: nil), generated)
    }
}
