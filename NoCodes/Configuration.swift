//
//  Configuration.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 28.03.2024.
//

import Foundation

extension NoCodes {
  
  /// Struct used to set the SDK main and additional configurations.
  public struct Configuration {
    
    /// Your project key from Qonversion Dashboard to setup the SDK
    let apiKey: String
    
    let delegate: NoCodes.Delegate?
    let screenCustomizationDelegate: NoCodes.ScreenCustomizationDelegate?
    
    /// Initializer of Configuration.
    ///
    /// Launch with ``Qonversion/LaunchMode/analytics`` mode to use Qonversion with your existing in-app subscription flow to get comprehensive subscription analytics and user engagement tools, and send the data to the leading marketing, analytics, and engagement platforms.
    /// - Important: Using ``Qonversion/LaunchMode/analytics`` you should process purchases by yourself. Qonversion SDK will only track revenue, but not finish transactions.
    /// - Parameters:
    ///   - apiKey: Your project key from Qonversion Dashboard to setup the SDK
    ///   - launchMode:launch mode of the Qonversion SDK.
    public init(apiKey: String, delegate: NoCodes.Delegate? = nil, screenCustomizationDelegate: NoCodes.ScreenCustomizationDelegate? = nil) {
      self.apiKey = apiKey
      self.delegate = delegate
      self.screenCustomizationDelegate = screenCustomizationDelegate
    }
    
  }
  
}
