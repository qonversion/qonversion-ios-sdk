import XCTest
@testable import NoCodes

#if os(iOS)

@MainActor
final class ConfigurationTests: XCTestCase {

    func testConfigurationKeepsTheCustomDefaultsInstance() {
        let defaults = TestDefaults.makeIsolated()
        let configuration = NoCodesConfiguration(
            projectKey: "key",
            userDefaults: defaults
        )

        XCTAssertTrue(configuration.userDefaults === defaults)
    }

    func testAssemblyWithoutCustomDefaultsUsesTheSdkSuite() {
        let suiteName = "io.qonversion.sdk"
        let sdkDefaults = UserDefaults(suiteName: suiteName)!
        sdkDefaults.removePersistentDomain(forName: suiteName)
        defer { sdkDefaults.removePersistentDomain(forName: suiteName) }

        let assembly = NoCodesAssembly(
            configuration: NoCodesConfiguration(projectKey: "key"),
            isFirstLaunch: false
        )
        assembly.miscAssembly.userDefaults.set("value", forKey: "test.internal-suite")

        XCTAssertEqual(sdkDefaults.string(forKey: "test.internal-suite"), "value")
    }
}

#endif
