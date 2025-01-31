//
//  NoCodes.swift
//  NoCodes
//
//  Created by Suren Sarkisyan on 17.12.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation

public final class NoCodes {
  
  // MARK: - Public
  
  /// Use this variable to get the current initialized instance of the Qonversion NoCodes SDK.
  /// Please, use the variable only after initializing the SDK.
  /// - Returns: the current initialized instance of the ``QonversionNoCodes/NoCodes`` SDK
  public static let shared = NoCodes()
  private var flowCoordinator: NoCodesFlowCoordinator? = nil
  
  @discardableResult
  public static func initialize(with configuration: Configuration) -> NoCodes {
    let assembly: NoCodesAssembly = NoCodesAssembly(configuration: configuration)
    NoCodes.shared.flowCoordinator = assembly.flowCoordinator()
    
    return NoCodes.shared
  }
  
  func set(delegate: NoCodes.Delegate) {
    flowCoordinator?.set(delegate: delegate)
  }
  
  func set(screenCustomizationDelegate: NoCodes.ScreenCustomizationDelegate) {
    flowCoordinator?.set(screenCustomizationDelegate: screenCustomizationDelegate)
  }
  
  @MainActor
  public func showNoCode(with id: String) async throws {
    try await flowCoordinator?.showNoCode(with: id)
  }
  
  public func close() {
    flowCoordinator?.close()
  }
  
}
