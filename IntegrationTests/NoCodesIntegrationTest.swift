//
//  NoCodesIntegrationTest.swift
//  IntegrationTests
//
//  Created by Kamo Spertsyan on 22.10.2025.
//  Copyright © 2025 Qonversion Inc. All rights reserved.
//

import Foundation
import XCTest
@testable import Qonversion

class NoCodesIntegrationTest: XCTestCase {
  
  // MARK: - Constants
  
  private let PROJECT_KEY = "V4pK6FQo3PiDPj_2vYO1qZpNBbFXNP-a"
  private let INCORRECT_PROJECT_KEY = "V4pK6FQo3PiDPj_2vYO1qZpNBbFXNP-aaaaa"
  
  private let VALID_CONTEXT_KEY = "test_context_key"
  private let ID_FOR_SCREEN_BY_CONTEXT_KEY = "KBxnTzQs"
  private let NON_EXISTENT_CONTEXT_KEY = "non_existent_test_context_key"
  
  private let VALID_SCREEN_ID = "RkgXghGq"
  private let CONTEXT_KEY_FOR_SCREEN_BY_ID = "another_test_context_key"
  private let NON_EXISTENT_SCREEN_ID = "non_existent_screen_id"
  
  private let REQUEST_TIMEOUT: TimeInterval = 10.0
  
  // MARK: - Test Methods
  
  func testGetScreenByContextKey() async throws {
    // given
    let noCodesService = getNoCodesService()
    
    // when
    let screen = try await noCodesService.loadScreen(withContextKey: VALID_CONTEXT_KEY)
    
    // then
    XCTAssertNotNil(screen, "Screen should not be null")
    XCTAssertEqual(screen.contextKey, VALID_CONTEXT_KEY, "Context key should match")
    XCTAssertNotNil(screen.html, "Screen content should exist")
    XCTAssertEqual(screen.id, ID_FOR_SCREEN_BY_CONTEXT_KEY, "Screen ID should match")
  }

  // Backend-independent: exercises NoCodesScreen decoding of the typed `variables` into
  // `defaultVariables` — kind (custom/product, tolerant), native value types, and the
  // defaulting when the key is absent. The shapes (space in key, empty-string default)
  // mirror real published_configs.
  func testScreenDecodesTypedDefaultVariables() throws {
    let decoder = JSONDecoder()

    // Array-nested shape (get-by-id `[{…}]`) → the unkeyed CodingKeys branch.
    let arrayJSON = """
    [{"id":"s1","body":"<html>","context_key":"ctx","variables":[\
    {"kind":"custom","key":"isTrial","type":"boolean","value":true},\
    {"kind":"custom","key":"headline","type":"string","value":"Go Premium"},\
    {"kind":"custom","key":"discount","type":"number","value":30},\
    {"kind":"custom","key":"custom var","type":"string","value":""},\
    {"kind":"product","key":"primary","type":"string","value":"weekly_299"}]}]
    """
    let arrayScreen = try decoder.decode(NoCodesScreen.self, from: Data(arrayJSON.utf8))
    XCTAssertEqual(arrayScreen.defaultVariables.map { $0.key }, ["isTrial", "headline", "discount", "custom var", "primary"])
    XCTAssertEqual(arrayScreen.defaultVariables[0].value, .bool(true))
    XCTAssertEqual(arrayScreen.defaultVariables[0].kind, .custom)
    XCTAssertEqual(arrayScreen.defaultVariables[1].value, .string("Go Premium"))
    XCTAssertEqual(arrayScreen.defaultVariables[2].value, .number(30))
    XCTAssertEqual(arrayScreen.defaultVariables[3].value, .string(""), "Empty-string default is preserved")
    XCTAssertEqual(arrayScreen.defaultVariables[4].kind, .product)
    XCTAssertEqual(arrayScreen.defaultVariables[4].value, .string("weekly_299"), "Product slot carries the default product id")

    // Keyed shape (by-context-key / preload / bundled fallback) → the ResponseCodingKeys branch.
    let keyedJSON = "{\"data\":{},\"id\":\"s2\",\"body\":\"<html>\",\"context_key\":\"ctx2\",\"variables\":[{\"kind\":\"product\",\"key\":\"primary\",\"type\":\"string\",\"value\":\"annual_4999\"}]}"
    let keyedScreen = try decoder.decode(NoCodesScreen.self, from: Data(keyedJSON.utf8))
    XCTAssertEqual(keyedScreen.defaultVariables.first?.value, .string("annual_4999"), "Variables should decode from the keyed response")

    // Missing variables key defaults to an empty array (no crash).
    let legacyJSON = "[{\"id\":\"s3\",\"body\":\"<html>\",\"context_key\":\"ctx3\"}]"
    let legacyScreen = try decoder.decode(NoCodesScreen.self, from: Data(legacyJSON.utf8))
    XCTAssertEqual(legacyScreen.defaultVariables.count, 0, "Missing variables should default to an empty array")
  }

  // Forward/backward wire compatibility of the `kind` field and the by-key lookup helper.
  func testVariableKindToleranceAndLookup() throws {
    let decoder = JSONDecoder()

    let json = """
    [{"id":"s1","body":"<html>","context_key":"ctx","variables":[\
    {"key":"legacy","type":"string","value":"pre-kind payload"},\
    {"kind":"device","key":"future","type":"string","value":"added later"},\
    {"kind":"custom","key":"known","type":"boolean","value":false},\
    {"kind":"custom","key":"primary","type":"string","value":"custom wins unfiltered"},\
    {"kind":"product","key":"primary","type":"string","value":"weekly_299"},\
    {"kind":"selected_product","key":"default_selected_product","type":"string","value":"annual"}]}]
    """
    let screen = try decoder.decode(NoCodesScreen.self, from: Data(json.utf8))

    // Missing kind (payload predating the field) → .custom; unknown kind → .unknown.
    XCTAssertEqual(screen.defaultVariables[0].kind, .custom, "Missing kind must default to custom")
    XCTAssertEqual(screen.defaultVariables[1].kind, .unknown, "Unknown kind must decode tolerantly")
    XCTAssertEqual(screen.defaultVariables[2].kind, .custom)
    XCTAssertEqual(screen.defaultVariables[5].kind, .selectedProduct, "selected_product must decode to the dedicated kind")

    // By-key lookup is exact and case-sensitive.
    XCTAssertEqual(screen.defaultVariable(forKey: "known")?.value, .bool(false))
    XCTAssertNil(screen.defaultVariable(forKey: "Known"))
    XCTAssertNil(screen.defaultVariable(forKey: "absent"))

    // Keys are only unique within a kind — the kind filter disambiguates collisions.
    XCTAssertEqual(screen.defaultVariable(forKey: "primary")?.kind, .custom, "Unfiltered lookup returns the first match in payload order")
    XCTAssertEqual(screen.defaultVariable(forKey: "primary", kind: .product)?.value, .string("weekly_299"))
    XCTAssertNil(screen.defaultVariable(forKey: "known", kind: .product))

    // The default selected product resolves via the typed shortcut — no magic key needed.
    XCTAssertEqual(screen.defaultSelectedProductId, "annual")
    let bareScreen = try decoder.decode(NoCodesScreen.self, from: Data("[{\"id\":\"s2\",\"body\":\"<html>\",\"context_key\":\"c\"}]".utf8))
    XCTAssertNil(bareScreen.defaultSelectedProductId, "No selected_product entry -> nil")
  }

  // stringValue renders any variable value as a plain string regardless of native type.
  func testVariableValueStringValue() {
    XCTAssertEqual(NoCodesScreenVariableValue.bool(true).stringValue, "true")
    XCTAssertEqual(NoCodesScreenVariableValue.bool(false).stringValue, "false")
    XCTAssertEqual(NoCodesScreenVariableValue.string("Go Premium").stringValue, "Go Premium")
    XCTAssertEqual(NoCodesScreenVariableValue.string("").stringValue, "")
    XCTAssertEqual(NoCodesScreenVariableValue.number(34).stringValue, "34", "Integral numbers must not carry a trailing .0")
    XCTAssertEqual(NoCodesScreenVariableValue.number(-2).stringValue, "-2")
    XCTAssertEqual(NoCodesScreenVariableValue.number(3.5).stringValue, "3.5")
    XCTAssertEqual(NoCodesScreenVariableValue.none.stringValue, "")
  }

  func testGetScreenById() async throws {
    // given
    let noCodesService = getNoCodesService()
    
    // when
    let screen = try await noCodesService.loadScreen(with: VALID_SCREEN_ID)
    
    // then
    XCTAssertNotNil(screen, "Screen should not be null")
    XCTAssertEqual(screen.id, VALID_SCREEN_ID, "Screen ID should match")
    XCTAssertNotNil(screen.html, "Screen content should exist")
    XCTAssertEqual(screen.contextKey, CONTEXT_KEY_FOR_SCREEN_BY_ID, "Context key should match")
  }

  // MARK: - loadScreen(withContextKey:) — load-before-present

  func testLoadScreenByContextKeyReturnsScreenWithPublicIdentifiers() async throws {
    // given
    let flowCoordinator = getFlowCoordinator()

    // when
    let screen = try await flowCoordinator.loadScreen(withContextKey: VALID_CONTEXT_KEY)

    // then
    // The public identifiers must be readable by consumers outside the module.
    XCTAssertEqual(screen.contextKey, VALID_CONTEXT_KEY, "Public context key should match")
    XCTAssertEqual(screen.id, ID_FOR_SCREEN_BY_CONTEXT_KEY, "Public screen ID should match")
  }

  func testLoadScreenByContextKeyNotFoundThrowsScreenNotFound() async {
    // given
    let flowCoordinator = getFlowCoordinator()

    // when
    do {
      _ = try await flowCoordinator.loadScreen(withContextKey: NON_EXISTENT_CONTEXT_KEY)
      XCTFail("Should fail with non-existent context key")
    } catch {
      // then
      XCTAssertEqual((error as? NoCodesError)?.type, NoCodesErrorType.screenNotFound, "Error type should be screenNotFound")
    }
  }

  func testLoadScreenWarmsCacheForSubsequentLoad() async throws {
    // given
    // Drive the service with a counting request processor so we can prove the second load is served
    // from cache rather than the network — a live-backend variant would pass even with no caching.
    let expectedScreen = NoCodesScreen(id: ID_FOR_SCREEN_BY_CONTEXT_KEY, html: "<html></html>", contextKey: VALID_CONTEXT_KEY)
    let requestProcessor = CountingRequestProcessor(screens: [expectedScreen])
    let noCodesService = NoCodesService(requestProcessor: requestProcessor)

    // when
    let firstLoad = try await noCodesService.loadScreen(withContextKey: VALID_CONTEXT_KEY)
    let secondLoad = try await noCodesService.loadScreen(withContextKey: VALID_CONTEXT_KEY)

    // then
    XCTAssertEqual(firstLoad.id, secondLoad.id, "Cached load should return the same screen ID")
    XCTAssertEqual(firstLoad.contextKey, secondLoad.contextKey, "Cached load should return the same context key")
    XCTAssertEqual(requestProcessor.processCallCount, 1, "Second load should be served from cache without a second network request")
  }

  func testLoadScreenFiresNoScreenEvents() async throws {
    // given
    let spyScreenEventsService = SpyScreenEventsService()
    let flowCoordinator = makeFlowCoordinator(
      noCodesService: MockNoCodesService(screen: NoCodesScreen(id: ID_FOR_SCREEN_BY_CONTEXT_KEY, html: "<html></html>", contextKey: VALID_CONTEXT_KEY)),
      screenEventsService: spyScreenEventsService
    )

    // when
    _ = try await flowCoordinator.loadScreen(withContextKey: VALID_CONTEXT_KEY)

    // then
    // Loading without presenting must not emit an impression — those fire only in the presentation path.
    XCTAssertTrue(spyScreenEventsService.trackedEvents.isEmpty, "Load-only should not fire any screen events")
  }

  func testPreloadScreens() async throws {
    // given
    let noCodesService = getNoCodesService()
    
    // when
    let screens = try await noCodesService.preloadScreens()
    
    // then
    XCTAssertNotNil(screens, "Screens list should not be null")
    XCTAssertEqual(screens.count, 2, "Should preload two screens")
    
    // Check first screen (order may vary)
    let firstScreen = screens.first { $0.id == ID_FOR_SCREEN_BY_CONTEXT_KEY }
    XCTAssertNotNil(firstScreen, "First screen should exist")
    XCTAssertNotNil(firstScreen?.html, "Screen content should exist")
    XCTAssertEqual(firstScreen?.contextKey, VALID_CONTEXT_KEY, "Context key for first screen should match")
    
    // Check second screen
    let secondScreen = screens.first { $0.id == VALID_SCREEN_ID }
    XCTAssertNotNil(secondScreen, "Second screen should exist")
    XCTAssertNotNil(secondScreen?.html, "Screen content should exist")
    XCTAssertEqual(secondScreen?.contextKey, CONTEXT_KEY_FOR_SCREEN_BY_ID, "Context key for second screen should match")
  }
  
  func testGetScreenWithIncorrectProjectKey() async {
    // given
    let noCodesService = getNoCodesService(projectKey: INCORRECT_PROJECT_KEY)
    
    // when
    do {
      _ = try await noCodesService.loadScreen(withContextKey: VALID_CONTEXT_KEY)
      XCTFail("Should fail with incorrect project key")
    } catch {
      // then
      XCTAssertTrue(error is NoCodesError, "Error should be NoCodesError")
      XCTAssertEqual(((error as? NoCodesError)?.error as? NoCodesError)?.type, NoCodesErrorType.critical, "Nested error type should be critical")
    }
  }
  
  func testGetScreenWithNonExistentContextKey() async {
    // given
    let noCodesService = getNoCodesService()

    // when
    do {
      _ = try await noCodesService.loadScreen(withContextKey: NON_EXISTENT_CONTEXT_KEY)
      XCTFail("Should fail with non-existent context key")
    } catch {
      // then
      // A genuinely absent screen is surfaced unwrapped, so callers can branch on the top-level type.
      XCTAssertTrue(error is NoCodesError, "Error should be NoCodesError")
      XCTAssertEqual((error as? NoCodesError)?.type, NoCodesErrorType.screenNotFound, "Error type should be screenNotFound")
    }
  }

  func testGetScreenWithEmptyContextKey() async {
    // given
    let noCodesService = getNoCodesService()

    // when
    do {
      _ = try await noCodesService.loadScreen(withContextKey: "")
      XCTFail("Should fail with empty context key")
    } catch {
      // then
      // A genuinely absent screen is surfaced unwrapped, so callers can branch on the top-level type.
      XCTAssertTrue(error is NoCodesError, "Error should be NoCodesError")
      XCTAssertEqual((error as? NoCodesError)?.type, NoCodesErrorType.screenNotFound, "Error type should be screenNotFound")
    }
  }
  
  func testGetScreenByIdWithIncorrectProjectKey() async {
    // given
    let noCodesService = getNoCodesService(projectKey: INCORRECT_PROJECT_KEY)
    
    // when
    do {
      _ = try await noCodesService.loadScreen(with: VALID_SCREEN_ID)
      XCTFail("Should fail with incorrect project key")
    } catch {
      // then
      XCTAssertTrue(error is NoCodesError, "Error should be NoCodesError")
      XCTAssertEqual(((error as? NoCodesError)?.error as? NoCodesError)?.type, NoCodesErrorType.critical, "Nested error type should be critical")
    }
  }
  
  func testGetScreenWithNonExistentId() async {
    // given
    let noCodesService = getNoCodesService()
    
    // when
    do {
      _ = try await noCodesService.loadScreen(with: NON_EXISTENT_SCREEN_ID)
      XCTFail("Should fail with non-existent screen ID")
    } catch {
      // then
      XCTAssertTrue(error is NoCodesError, "Error should be NoCodesError")
      XCTAssertEqual(((error as? NoCodesError)?.error as? NoCodesError)?.type, NoCodesErrorType.screenNotFound, "Nested error type should be screenNotFound")
    }
  }
  
  func testGetScreenWithEmptyId() async {
    // given
    let noCodesService = getNoCodesService()
    
    // when
    do {
      _ = try await noCodesService.loadScreen(with: "")
      XCTFail("Should fail with empty screen ID")
    } catch {
      // then
      XCTAssertTrue(error is NoCodesError, "Error should be NoCodesError")
      XCTAssertEqual(((error as? NoCodesError)?.error as? NoCodesError)?.type, NoCodesErrorType.screenNotFound, "Nested error type should be screenNotFound")
    }
  }
  
  func testPreloadScreensWithIncorrectProjectKey() async {
    // given
    let noCodesService = getNoCodesService(projectKey: INCORRECT_PROJECT_KEY)
    
    // when
    do {
      _ = try await noCodesService.preloadScreens()
      XCTFail("Should fail with incorrect project key")
    } catch {
      // then
      XCTAssertTrue(error is NoCodesError, "Error should be NoCodesError")
    }
  }
  
  // MARK: - Helper Methods
  
  private func getNoCodesService(projectKey: String? = nil) -> NoCodesServiceInterface {
    let key = projectKey ?? PROJECT_KEY
    let configuration = NoCodesConfiguration(projectKey: key)
    let assembly = NoCodesAssembly(configuration: configuration)
    let flowCoordinator = assembly.flowCoordinator()
    
    // Create a custom assembly for testing
    let miscAssembly = MiscAssembly(projectKey: key)
    let servicesAssembly = ServicesAssembly(miscAssembly: miscAssembly)
    miscAssembly.servicesAssembly = servicesAssembly

    return servicesAssembly.noCodesService()
  }

  private func getFlowCoordinator(projectKey: String? = nil) -> NoCodesFlowCoordinator {
    let key = projectKey ?? PROJECT_KEY
    let configuration = NoCodesConfiguration(projectKey: key)
    let assembly = NoCodesAssembly(configuration: configuration)

    return assembly.flowCoordinator()
  }

  private func makeFlowCoordinator(noCodesService: NoCodesServiceInterface, screenEventsService: ScreenEventsServiceInterface) -> NoCodesFlowCoordinator {
    // Inject test doubles for the load path while wiring the presentation-only dependencies from real assemblies.
    let miscAssembly = MiscAssembly(projectKey: PROJECT_KEY)
    let servicesAssembly = ServicesAssembly(miscAssembly: miscAssembly)
    miscAssembly.servicesAssembly = servicesAssembly
    let viewsAssembly = ViewsAssembly(miscAssembly: miscAssembly, servicesAssembly: servicesAssembly)

    return NoCodesFlowCoordinator(
      delegate: nil,
      screenCustomizationDelegate: nil,
      purchaseDelegate: nil,
      customVariablesDelegate: nil,
      noCodesService: noCodesService,
      screenEventsService: screenEventsService,
      viewsAssembly: viewsAssembly,
      logger: miscAssembly.loggerWrapper()
    )
  }
}

// MARK: - Test Doubles

private final class CountingRequestProcessor: RequestProcessorInterface {
  private let screens: [NoCodesScreen]
  private(set) var processCallCount = 0

  init(screens: [NoCodesScreen]) {
    self.screens = screens
  }

  func process<T>(request: Request, responseType: T.Type) async throws -> T where T : Decodable {
    processCallCount += 1
    // The context-key load path requests [NoCodesScreen]; this double only supports that path.
    guard let result = screens as? T else {
      throw NoCodesError(type: .invalidResponse)
    }

    return result
  }
}

private final class MockNoCodesService: NoCodesServiceInterface {
  private let screen: NoCodesScreen

  init(screen: NoCodesScreen) {
    self.screen = screen
  }

  func loadScreen(with id: String) async throws -> NoCodesScreen {
    return screen
  }

  func loadScreen(withContextKey contextKey: String) async throws -> NoCodesScreen {
    return screen
  }

  func preloadScreens() async throws -> [NoCodesScreen] {
    return [screen]
  }
}

private final class SpyScreenEventsService: ScreenEventsServiceInterface {
  private(set) var trackedEvents: [ScreenEvent] = []

  func track(event: ScreenEvent) {
    trackedEvents.append(event)
  }

  func flush() {}
}
