//
//  AsyncTestHelpers.swift
//  IntegrationTests
//
//  Created by Qonversion on 12.01.2026.
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

import Foundation
import XCTest

/// Error thrown when an async operation times out
struct AsyncTestTimeoutError: Error, LocalizedError {
  let timeout: TimeInterval
  
  var errorDescription: String? {
    return "Async operation timed out after \(timeout) seconds"
  }
}

/// Extension providing timeout functionality for async tests
extension XCTestCase {
  
  /// Executes an async operation with a timeout.
  /// If the operation doesn't complete within the specified timeout, an error is thrown.
  ///
  /// - Parameters:
  ///   - timeout: Maximum time to wait for the operation to complete (in seconds)
  ///   - operation: The async operation to execute
  /// - Returns: The result of the operation
  /// - Throws: `AsyncTestTimeoutError` if the operation times out, or any error thrown by the operation
  func withTimeout<T>(
    seconds timeout: TimeInterval,
    operation: @escaping () async throws -> T
  ) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
      // Add the main operation task
      group.addTask {
        try await operation()
      }
      
      // Add a timeout task
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        throw AsyncTestTimeoutError(timeout: timeout)
      }
      
      // Wait for the first task to complete
      guard let result = try await group.next() else {
        throw AsyncTestTimeoutError(timeout: timeout)
      }
      
      // Cancel remaining tasks
      group.cancelAll()
      
      return result
    }
  }
  
  /// Executes an async operation that is expected to throw an error, with a timeout.
  /// If the operation doesn't throw or times out, the test fails.
  ///
  /// - Parameters:
  ///   - timeout: Maximum time to wait for the operation to complete (in seconds)
  ///   - operation: The async operation to execute
  ///   - errorHandler: Closure to validate the thrown error
  func expectError(
    timeout: TimeInterval,
    from operation: @escaping () async throws -> Void,
    errorHandler: (Error) -> Void
  ) async {
    do {
      try await withTimeout(seconds: timeout) {
        try await operation()
      }
      XCTFail("Expected operation to throw an error, but it succeeded")
    } catch is AsyncTestTimeoutError {
      XCTFail("Operation timed out after \(timeout) seconds")
    } catch {
      errorHandler(error)
    }
  }
}
