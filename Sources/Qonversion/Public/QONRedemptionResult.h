//
//  QONRedemptionResult.h
//  Qonversion
//
//  Result of a Web 2 App redemption attempt (DEV-847 / M1).
//

#import <Foundation/Foundation.h>

/**
 Outcome of a Web 2 App redemption attempt.

 Cases are intentionally limited (6 cases) so host apps can map each value 1:1
 to a concrete UX state. Adding cases requires a design decision; do not extend
 ad-hoc.
 */
typedef NS_ENUM(NSInteger, QONRedemptionResult) {
  /// Token consumed; entitlement granted. Under grant-first the backend has
  /// ALREADY granted the entitlement server-side, so the SDK does NOT call
  /// `identify`/merge — it only triggers an entitlements refresh
  /// (ActualizePermissions). The host app's next `checkEntitlements` will
  /// include the redeemed product. Do NOT add your own `identify` call here.
  QONRedemptionResultSuccess = 0,

  /// Token TTL elapsed before it could be redeemed. Host app should offer
  /// the reissue flow (`presentReissueUI`).
  QONRedemptionResultTokenExpired = 1,

  /// Server responded 409 and `/v4/web/redeem/status` confirms the token has
  /// already been consumed (redeemed previously). This is a terminal outcome
  /// for the link; the host app should inform the user the link was already
  /// used. The SDK does not attempt any `identify`-based recovery.
  QONRedemptionResultAlreadyConsumed = 2,

  /// Token not found (404). Likely tampered, mistyped, or stale link.
  QONRedemptionResultInvalidToken = 3,

  /// Could not reach the Qonversion backend (DNS / TCP / TLS / timeout).
  /// This means the device genuinely failed to talk to the server — it is
  /// NOT used for live server responses such as 429/5xx (see `.retryable`).
  QONRedemptionResultNetworkError = 4,

  /// The backend was reachable but returned a transient/server-side outcome
  /// that the host app may safely retry later: rate limiting (429), server
  /// errors (5xx), or auth/config errors (other non-mapped 4xx such as
  /// 401/403). Also surfaced for SDK-side preconditions that can be retried
  /// once the SDK has a usable anonymous user id. Distinguishing this from
  /// `.networkError` avoids the misleading "no internet" UX when the network
  /// is in fact live and the server simply asked the client to back off.
  QONRedemptionResultRetryable = 5,
} NS_SWIFT_NAME(Qonversion.RedemptionResult);
