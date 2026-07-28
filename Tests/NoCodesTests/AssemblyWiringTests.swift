//
//  AssemblyWiringTests.swift
//  NoCodesTests
//
//  The object graph builds without back references and shares the instances
//  that must be shared.
//

import XCTest
@testable import NoCodes

@MainActor
final class AssemblyWiringTests: XCTestCase {

    func testTheRequestProcessorBuildsWithoutAnAssemblyBackReference() {
        let miscAssembly = MiscAssembly(projectKey: "project-key")
        let servicesAssembly = ServicesAssembly(miscAssembly: miscAssembly)

        // Before, the headers builder reached back into the services assembly
        // through a weak implicitly unwrapped property; the collector is now
        // handed in by the assembly that owns it. Building the processor is the
        // assertion — an unset back reference traps inside this call.
        _ = servicesAssembly.requestProcessor()
    }

    func testTheSharedServicesAreBuiltOnce() {
        let miscAssembly = MiscAssembly(projectKey: "project-key")
        let servicesAssembly = ServicesAssembly(miscAssembly: miscAssembly)

        let firstProcessor: RequestProcessorInterface = servicesAssembly.requestProcessor()
        let secondProcessor: RequestProcessorInterface = servicesAssembly.requestProcessor()
        let firstService: NoCodesServiceInterface = servicesAssembly.noCodesService()
        let secondService: NoCodesServiceInterface = servicesAssembly.noCodesService()
        let firstEvents: ScreenEventsServiceInterface = servicesAssembly.screenEventsService()
        let secondEvents: ScreenEventsServiceInterface = servicesAssembly.screenEventsService()

        XCTAssertTrue(firstProcessor as AnyObject === secondProcessor as AnyObject)
        XCTAssertTrue(firstService as AnyObject === secondService as AnyObject)
        XCTAssertTrue(firstEvents as AnyObject === secondEvents as AnyObject)
    }

    func testTheDeviceInfoCollectorIsSharedAndSnapshotted() {
        let miscAssembly = MiscAssembly(projectKey: "project-key")
        let servicesAssembly = ServicesAssembly(miscAssembly: miscAssembly)

        let first: DeviceInfoCollectorInterface = servicesAssembly.deviceInfoCollector()
        let second: DeviceInfoCollectorInterface = servicesAssembly.deviceInfoCollector()

        XCTAssertTrue(first as AnyObject === second as AnyObject)
        // The record is captured once at construction, so repeated reads match.
        XCTAssertEqual(first.deviceInfo().osVersion, second.deviceInfo().osVersion)
        XCTAssertFalse(first.deviceInfo().osVersion.isEmpty)
    }

    func testTheHeadersBuilderTakesTheCollectorAsAParameter() {
        let miscAssembly = MiscAssembly(projectKey: "project-key")
        let servicesAssembly = ServicesAssembly(miscAssembly: miscAssembly)
        let deviceInfoCollector: DeviceInfoCollectorInterface = servicesAssembly.deviceInfoCollector()
        let headersBuilder: HeadersBuilderInterface = miscAssembly.headersBuilder(deviceInfoCollector: deviceInfoCollector)
        let url = URL(string: "https://api2.qonversion.io/v3/screens/screen-1")!
        var request = URLRequest(url: url)

        headersBuilder.addHeaders(to: &request)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer project-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Platform-Version"), deviceInfoCollector.deviceInfo().osVersion)
    }
}
