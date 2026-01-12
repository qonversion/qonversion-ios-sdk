//
//  NoCodesOutagerIntegrationTest.swift
//  IntegrationTests
//
//  Created by Kamo Spertsyan on 22.10.2025.
//  Copyright © 2025 Qonversion Inc. All rights reserved.
//

import Foundation
import XCTest
@testable import Qonversion

class NoCodesOutagerIntegrationTest: XCTestCase {
  
  // MARK: - Constants
  
  private let PROJECT_KEY = "V4pK6FQo3PiDPj_2vYO1qZpNBbFXNP-a"
  private let INCORRECT_PROJECT_KEY = "V4pK6FQo3PiDPj_2vYO1qZpNBbFXNP-aaaaa"
  
  private let VALID_CONTEXT_KEY = "test_context_key"
  private let ID_FOR_SCREEN_BY_CONTEXT_KEY = "KBxnTzQs"
  private let NON_EXISTENT_CONTEXT_KEY = "non_existent_test_context_key"
  
  private let VALID_SCREEN_ID = "RkgXghGq"
  private let CONTEXT_KEY_FOR_SCREEN_BY_ID = "another_test_context_key"
  private let NON_EXISTENT_SCREEN_ID = "non_existent_screen_id"
  
  private let REQUEST_TIMEOUT: TimeInterval = 30.0
  
  // MARK: - Test Methods
  
  func testGetScreenByContextKey() async throws {
    // given
    let noCodesService = getNoCodesService()
    
    // when
    let screen = try await withTimeout(seconds: REQUEST_TIMEOUT) {
      try await noCodesService.loadScreen(withContextKey: self.VALID_CONTEXT_KEY)
    }
    
    // then
    XCTAssertNotNil(screen, "Screen should not be null")
    XCTAssertEqual(screen.contextKey, VALID_CONTEXT_KEY, "Context key should match")
    XCTAssertNotNil(screen.html, "Screen content should exist")
    XCTAssertEqual(screen.id, ID_FOR_SCREEN_BY_CONTEXT_KEY, "Screen ID should match")
  }
  
  func testGetScreenById() async throws {
    // given
    let noCodesService = getNoCodesService()
    
    // when
    let screen = try await withTimeout(seconds: REQUEST_TIMEOUT) {
      try await noCodesService.loadScreen(with: self.VALID_SCREEN_ID)
    }
    
    // then
    XCTAssertNotNil(screen, "Screen should not be null")
    XCTAssertEqual(screen.id, VALID_SCREEN_ID, "Screen ID should match")
    XCTAssertNotNil(screen.html, "Screen content should exist")
    XCTAssertEqual(screen.contextKey, CONTEXT_KEY_FOR_SCREEN_BY_ID, "Context key should match")
  }
  
  func testPreloadScreens() async throws {
    // given
    let noCodesService = getNoCodesService()
    
    // when
    let screens = try await withTimeout(seconds: REQUEST_TIMEOUT) {
      try await noCodesService.preloadScreens()
    }
    
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
  
  func testGetScreenWithNonExistentContextKey() async {
    // given
    let noCodesService = getNoCodesService()
    
    // when
    await expectError(timeout: REQUEST_TIMEOUT) {
      _ = try await noCodesService.loadScreen(withContextKey: self.NON_EXISTENT_CONTEXT_KEY)
    } errorHandler: { error in
      // then
      XCTAssertTrue(error is NoCodesError, "Error should be NoCodesError")
      XCTAssertEqual(((error as? NoCodesError)?.error as? NoCodesError)?.type, NoCodesErrorType.screenNotFound, "Nested error type should be screenNotFound")
    }
  }
  
  func testGetScreenWithEmptyContextKey() async {
    // given
    let noCodesService = getNoCodesService()
    
    // when
    await expectError(timeout: REQUEST_TIMEOUT) {
      _ = try await noCodesService.loadScreen(withContextKey: "")
    } errorHandler: { error in
      // then
      XCTAssertTrue(error is NoCodesError, "Error should be NoCodesError")
      XCTAssertEqual(((error as? NoCodesError)?.error as? NoCodesError)?.type, NoCodesErrorType.screenNotFound, "Nested error type should be screenNotFound")
    }
  }
  
  func testGetScreenWithNonExistentId() async {
    // given
    let noCodesService = getNoCodesService()
    
    // when
    await expectError(timeout: REQUEST_TIMEOUT) {
      _ = try await noCodesService.loadScreen(with: self.NON_EXISTENT_SCREEN_ID)
    } errorHandler: { error in
      // then
      XCTAssertTrue(error is NoCodesError, "Error should be NoCodesError")
      XCTAssertEqual(((error as? NoCodesError)?.error as? NoCodesError)?.type, NoCodesErrorType.screenNotFound, "Nested error type should be screenNotFound")
    }
  }
  
  // MARK: - Helper Methods
  
  private func getNoCodesService() -> NoCodesServiceInterface {
    // Create a custom assembly for Outager testing
    let miscAssembly = MiscAssembly(projectKey: PROJECT_KEY)
    let outagerAssembly = OutagerServicesAssembly(miscAssembly: miscAssembly)
    
    return outagerAssembly.noCodesService()
  }
  
  // MARK: - Outager Services Assembly
  
  private class OutagerServicesAssembly {
    private let miscAssembly: MiscAssembly
    private let servicesAssembly: ServicesAssembly
    
    init(miscAssembly: MiscAssembly) {
      self.miscAssembly = miscAssembly
      self.servicesAssembly = ServicesAssembly(miscAssembly: miscAssembly)
      // Set the circular reference
      miscAssembly.servicesAssembly = servicesAssembly
    }
    
    func noCodesService() -> NoCodesServiceInterface {
      // Create a custom request processor with Outager URL
      let networkProvider: NetworkProviderInterface = servicesAssembly.networkProvider()
      let headersBuilder: HeadersBuilderInterface = miscAssembly.headersBuilder()
      let errorHandler: NetworkErrorHandlerInterface = miscAssembly.errorHandler()
      let decoder: ResponseDecoderInterface = miscAssembly.responseDecoder()
      let rateLimiter: RateLimiterInterface = miscAssembly.rateLimiter()
      
      let retriableRequestsList: [Request] = []
      
      // Use Outager URL instead of default API URL
      let processor = RequestProcessor(baseURL: "<paste outager link here>", networkProvider: networkProvider, headersBuilder: headersBuilder, errorHandler: errorHandler, decoder: decoder, retriableRequestsList: retriableRequestsList, rateLimiter: rateLimiter)
      
      // Create NoCodesService with custom processor
      return NoCodesService(requestProcessor: processor, fallbackService: servicesAssembly.fallbackService())
    }
  }
}
