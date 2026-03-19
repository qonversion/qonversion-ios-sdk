//
//  NoCodesLoadingView.swift
//  NoCodes
//
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

import Foundation

#if os(iOS)
import UIKit

/// Protocol for custom loading views displayed while NoCodes screens are loading.
/// Conforming types must be UIView subclasses.
public protocol NoCodesLoadingView where Self: UIView {
  /// Called when the loading view should start its loading animation.
  func startAnimating()
  /// Called when the loading view should stop its loading animation.
  func stopAnimating()
}

#endif
