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

/// Executes an async operation with a timeout.
/// Uses Task.sleep for timeout and cancels the operation if it exceeds the limit.
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
  return try await withThrowingTaskGroup(of: T.self) { group in
    // Add the main operation
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

/// Executes an async operation that is expected to throw an error.
/// If the operation doesn't throw, the test fails.
///
/// - Parameters:
///   - timeout: Maximum time to wait for the operation to complete (in seconds)
///   - operation: The async operation to execute
/// - Returns: The error that was thrown, or nil if the operation succeeded (and XCTFail was called)
func expectError(
  timeout: TimeInterval,
  from operation: @escaping () async throws -> Void
) async -> Error? {
  do {
    try await withTimeout(seconds: timeout) {
      try await operation()
    }
    XCTFail("Expected operation to throw an error, but it succeeded")
    return nil
  } catch {
    return error
  }
}
