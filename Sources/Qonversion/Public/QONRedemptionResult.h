//
//  QONRedemptionResult.h
//  Qonversion
//
//  Result of a Web 2 App redemption attempt (DEV-847 / M1).
//

#import <Foundation/Foundation.h>

/**
 Outcome of a Web 2 App redemption attempt.

 Cases are intentionally limited per Decision #3 r6 ("5-case enum") so host
 apps can map each value 1:1 to a concrete UX state. Adding cases requires
 a design decision; do not extend ad-hoc.
 */
typedef NS_ENUM(NSInteger, QONRedemptionResult) {
  /// Token consumed; entitlement granted. The SDK has already issued the
  /// internal `identify` call to merge anon→app, so the next entitlements
  /// fetch will include the redeemed product.
  QONRedemptionResultSuccess = 0,

  /// Token TTL elapsed before it could be redeemed. Host app should offer
  /// the reissue flow (`presentReissueUI`).
  QONRedemptionResultTokenExpired = 1,

  /// Server responded 409 and `/v4/web/redeem/status` confirms the token
  /// has already been consumed. Host app may need to call
  /// `Qonversion.shared().identify(userID:)` if the original purchaser's
  /// user id is known.
  QONRedemptionResultAlreadyConsumed = 2,

  /// Token not found (404). Likely tampered, mistyped, or stale link.
  QONRedemptionResultInvalidToken = 3,

  /// Could not reach the Qonversion backend (DNS / TCP / TLS / timeout).
  QONRedemptionResultNetworkError = 4,
} NS_SWIFT_NAME(Qonversion.RedemptionResult);
