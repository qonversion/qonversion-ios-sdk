//
//  QONRedemptionManager.h
//  Qonversion
//
//  Web 2 App redemption — parses Universal Link, calls
//  /v4/web/redeem*, maps HTTP outcome to QONRedemptionResult,
//  and on success triggers an entitlements refresh (the server has
//  already granted the entitlement under grant-first; the SDK does NOT
//  call identify/merge).
//

#import <Foundation/Foundation.h>
#import "QONRedemptionResult.h"

@class QNProductCenterManager;
@protocol QNUserInfoServiceInterface;

NS_ASSUME_NONNULL_BEGIN

typedef void (^QONRedemptionCompletionHandler)(QONRedemptionResult result);
typedef void (^QONReissueCompletionHandler)(BOOL success, NSInteger statusCode, NSError * _Nullable error);

@interface QONRedemptionManager : NSObject

@property (nonatomic, weak) QNProductCenterManager *productCenterManager;
@property (nonatomic, strong) id<QNUserInfoServiceInterface> userInfoService;

/// Test seam. Defaults to a session created from `defaultSessionConfiguration`.
@property (nonatomic, strong) NSURLSession *session;

/// Test seam. Defaults to `kAPIBase`.
@property (nonatomic, copy) NSString *baseURL;

/// Parse a Universal Link of the form
///   `https://<host>/r/{project_uid}/{token}`
/// and run the redemption flow. The completion is dispatched on the main queue.
///
/// On `QONRedemptionResultSuccess` the entitlement has already been granted
/// server-side for the current user; the SDK triggers an entitlements
/// refresh so the host app's next `checkEntitlements:` includes the redeemed
/// product. The SDK does NOT call identify/merge.
- (void)handleRedemptionLink:(NSURL *)url completion:(QONRedemptionCompletionHandler)completion;

/// POST `/v4/web/redeem/reissue` with the supplied email.
/// `success` is YES for HTTP 2xx, NO otherwise. `statusCode` lets the caller
/// distinguish 429 (rate limited) from 5xx (server error) for messaging.
- (void)reissueWithEmail:(NSString *)email completion:(QONReissueCompletionHandler)completion;

/// Public for unit tests; not part of the SDK's stable surface.
+ (nullable NSString *)tokenFromURL:(NSURL *)url;

@end

NS_ASSUME_NONNULL_END
