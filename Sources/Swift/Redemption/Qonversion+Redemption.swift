//
//  Qonversion+Redemption.swift
//  Qonversion
//
//  Public Swift surface for Web 2 App redemption (DEV-847 / M1).
//
//  Mirrors the spec from §"Mobile SDK API surface → iOS":
//    - `handleRedemptionLink(url:completion:)` — PRIMARY: host app forwards
//       its Universal Link from the email→app flow.
//    - `presentReissueUI(from:onCompletion:)` — FALLBACK UI: when the token
//       expired or install attribution failed.
//
//  Note: under grant-first the backend already grants the entitlement on a
//  successful redeem. The SDK does NOT call identify/merge; it only triggers
//  an entitlements refresh. Host app should not call identify as part of
//  redemption either.
//

import Foundation
@_exported import Qonversion

#if canImport(UIKit) && (os(iOS) || os(tvOS) || os(visionOS))
import UIKit

extension Qonversion {

  /// PRIMARY entry point. Host app forwards a Universal Link received via
  /// `application(_:continue:restorationHandler:)` from the email→app
  /// redemption flow.
  ///
  /// Expected URL shape: `https://<host>/r/{project_uid}/{token}`.
  ///
  /// Completion is invoked on the main queue. On `.success` the entitlement
  /// has already been granted server-side; the SDK triggers an entitlements
  /// refresh so the host app's next `checkEntitlements` call sees the
  /// redeemed entitlement. The SDK does not call identify/merge.
  ///
  /// - Parameters:
  ///   - url: Universal Link to parse.
  ///   - completion: Outcome callback (main queue).
  @objc public static func handleRedemptionLink(
    url: URL,
    completion: @escaping (Qonversion.RedemptionResult) -> Void
  ) {
    Qonversion.shared().handleRedemptionLink(url: url, completion: completion)
  }

  /// FALLBACK UI. Presents a modal asking the user for their email and
  /// POSTs `/v4/web/redeem/reissue` to trigger a new redemption email.
  ///
  /// Use this when:
  ///  - the token-based redemption resulted in `.tokenExpired`, or
  ///  - install attribution failed and the host app couldn't auto-redeem.
  ///
  /// `onCompletion(true)` is called after the user has successfully
  /// submitted an email (HTTP 2xx). `onCompletion(false)` is called if the
  /// user cancels.
  ///
  /// - Parameters:
  ///   - viewController: Presenter for the modal.
  ///   - onCompletion: `true` if the email was submitted successfully,
  ///     `false` if the user dismissed without submitting.
  @available(iOS 13.0, tvOS 13.0, *)
  @objc public func presentReissueUI(
    from viewController: UIViewController,
    onCompletion: @escaping (Bool) -> Void
  ) {
    let reissueVC = ReissueViewController(onCompletion: onCompletion)
    // `.formSheet` requires tvOS 26+; use full screen on tvOS so the
    // multi-platform podspec lint compiles on older deployment targets.
    #if os(tvOS)
    reissueVC.modalPresentationStyle = .fullScreen
    #else
    reissueVC.modalPresentationStyle = .formSheet
    #endif
    viewController.present(reissueVC, animated: true)
  }
}

#else

// On platforms without UIKit (macOS, watchOS) we still expose
// handleRedemptionLink so SPM consumers building for those targets
// compile cleanly. `presentReissueUI` is gated behind UIKit.

extension Qonversion {

  @objc public static func handleRedemptionLink(
    url: URL,
    completion: @escaping (Qonversion.RedemptionResult) -> Void
  ) {
    Qonversion.shared().handleRedemptionLink(url: url, completion: completion)
  }
}

#endif
