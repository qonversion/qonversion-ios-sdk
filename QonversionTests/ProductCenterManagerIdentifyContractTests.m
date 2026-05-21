#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>
#import "QNProductCenterManager.h"
#import "QNAPIClient.h"
#import "QNUserDefaultsStorage.h"
#import "QNStoreKitService.h"
#import "QONLaunchResult.h"
#import "QONLaunchResult+Protected.h"
#import "QNUserInfoService.h"
#import "QNIdentityManager.h"
#import "QNLocalStorage.h"
#import "QONFallbackService.h"
#import "QONRemoteConfigManager.h"
#import "QONRequestTrigger.h"

/*
 * Web 2 App M1 [RT5-N2] — contract tests for -[QNProductCenterManager processIdentity:].
 *
 * The /v4/web/redeem/status recovery UX (DEV-845 plan §"POST /v4/web/redeem/status")
 * relies on `Qonversion.identify(userID:)` triggering a fresh entitlement fetch via
 * the merged identity. The SDK honours this implicitly in `processIdentity:`:
 * when the new identity differs from the current user id (QNProductCenterManager.m:313),
 * the manager calls `resetActualPermissionsCache` THEN `launchWithTrigger:QONRequestTriggerIdentify`.
 *
 * If a future SDK change defers or skips the launch step (e.g. lazy-fetch on next
 * checkEntitlements call), the web→app recovery flow silently breaks — the user
 * signs in but the server-side entitlement never reaches the host app. These tests
 * pin the contract so any regression fails CI.
 *
 * Source of truth: QNProductCenterManager.m:292-327.
 * Symmetric Android contract test lives in:
 *   android-sdk/sdk/src/test/.../QProductCenterManagerIdentifyContractTest.kt
 */

@interface QNProductCenterManager (IdentifyContractPrivate)

@property (nonatomic) QNAPIClient *apiClient;
@property (nonatomic) QONLaunchResult *launchResult;
@property (nonatomic) NSError *launchError;
@property (nonatomic, assign) BOOL launchingFinished;
@property (nonatomic, assign) BOOL identityInProgress;

- (void)processIdentity:(NSString *)identityId;
- (void)resetActualPermissionsCache;

@end

@interface ProductCenterManagerIdentifyContractTests : XCTestCase

@property (nonatomic, strong) id mockClient;
@property (nonatomic, strong) id mockUserInfoService;
@property (nonatomic, strong) id mockIdentityManager;
@property (nonatomic, strong) id mockRemoteConfigManager;
@property (nonatomic, strong) id partialManagerMock;
@property (nonatomic, strong) QNProductCenterManager *manager;

@end

@implementation ProductCenterManagerIdentifyContractTests

- (void)setUp {
  _mockClient = OCMClassMock([QNAPIClient class]);
  OCMStub([_mockClient shared]).andReturn(_mockClient);

  _mockUserInfoService = OCMProtocolMock(@protocol(QNUserInfoServiceInterface));
  _mockIdentityManager = OCMClassMock([QNIdentityManager class]);
  id mockLocalStorage = OCMProtocolMock(@protocol(QNLocalStorage));
  id mockFallbackService = OCMClassMock([QONFallbackService class]);

  _manager = [[QNProductCenterManager alloc] initWithUserInfoService:_mockUserInfoService
                                                     identityManager:_mockIdentityManager
                                                        localStorage:mockLocalStorage
                                                     fallbackService:mockFallbackService];
  [_manager setApiClient:_mockClient];

  _mockRemoteConfigManager = OCMClassMock([QONRemoteConfigManager class]);
  _manager.remoteConfigManager = _mockRemoteConfigManager;

  // Wrap the manager so we can verify the call to -resetActualPermissionsCache
  // and intercept -launchWithTrigger:completion: (the launch method runs a long
  // initialisation flow we don't want to actually execute in unit tests).
  _partialManagerMock = OCMPartialMock(_manager);
}

- (void)tearDown {
  [_partialManagerMock stopMocking];
  [_mockClient stopMocking];
  _manager = nil;
}

#pragma mark - RT5-N2 contract

/*
 * Happy path — identity manager succeeds with a DIFFERENT qonversion uid
 * (the cross-user-success branch). The manager MUST:
 *   1. Set the new user id on the API client.
 *   2. Inform the remote config manager.
 *   3. Reset the cached permissions (so launch returns fresh data).
 *   4. Issue launchWithTrigger:QONRequestTriggerIdentify.
 *
 * These four side effects are the contract the web→app recovery flow
 * depends on. If any is dropped, the host app's "Sign in to restore"
 * call returns success but the entitlement is never delivered.
 */
- (void)testProcessIdentity_DifferentUid_ResetsCacheAndLaunchesWithIdentifyTrigger {
  NSString *identityId = @"user@example.com";
  NSString *currentUid = @"uid_initial";
  NSString *mergedUid = @"uid_merged_999";

  OCMStub([_mockUserInfoService obtainUserID]).andReturn(currentUid);
  // identityManager.identify(identityId, completion) → success with mergedUid
  OCMStub([_mockIdentityManager identify:identityId completion:[OCMArg invokeBlockWithArgs:mergedUid, [NSNull null], nil]]);

  // We intercept resetActualPermissionsCache to verify it's called.
  OCMExpect([_partialManagerMock resetActualPermissionsCache]);

  // We intercept launchWithTrigger:completion: to verify the trigger and
  // avoid actually firing the launch network call.
  OCMExpect([_partialManagerMock launchWithTrigger:QONRequestTriggerIdentify completion:[OCMArg any]]);

  // When
  [_partialManagerMock processIdentity:identityId];

  // Then
  OCMVerify([_mockClient setUserID:mergedUid]);
  OCMVerify([_mockRemoteConfigManager userHasBeenChanged]);
  OCMVerifyAll(_partialManagerMock); // resetActualPermissionsCache + launchWithTrigger
}

/*
 * Same-uid case: the user "identifies" with what is effectively the same
 * Qonversion uid (e.g. host app calls identify again with no real switch).
 * The manager MUST NOT clear the permissions cache nor re-launch — that
 * would waste a request, briefly flash entitlement-empty UI to legit
 * users, and risk a race with in-flight callbacks.
 */
- (void)testProcessIdentity_SameUid_DoesNotResetCacheOrRelaunch {
  NSString *identityId = @"user@example.com";
  NSString *sameUid = @"uid_initial";

  OCMStub([_mockUserInfoService obtainUserID]).andReturn(sameUid);
  OCMStub([_mockIdentityManager identify:identityId completion:[OCMArg invokeBlockWithArgs:sameUid, [NSNull null], nil]]);

  // Negative expectations — these methods MUST NOT be called.
  OCMReject([_partialManagerMock resetActualPermissionsCache]);
  OCMReject([_partialManagerMock launchWithTrigger:QONRequestTriggerIdentify completion:[OCMArg any]]);

  // When
  [_partialManagerMock processIdentity:identityId];

  // Then — if either rejected call fired, OCMReject already failed the test.
  OCMVerifyAll(_partialManagerMock);
}

/*
 * Identity manager returns an error — the recovery UX bails out cleanly:
 * no cache reset, no launch. The prior cached entitlements stay intact
 * so existing app behaviour is unaffected.
 */
- (void)testProcessIdentity_IdentityError_DoesNotResetCacheOrRelaunch {
  NSString *identityId = @"user@example.com";
  NSError *bang = [NSError errorWithDomain:@"QonversionTests" code:-1 userInfo:nil];

  OCMStub([_mockUserInfoService obtainUserID]).andReturn(@"uid_initial");
  OCMStub([_mockIdentityManager identify:identityId completion:[OCMArg invokeBlockWithArgs:[NSNull null], bang, nil]]);

  OCMReject([_partialManagerMock resetActualPermissionsCache]);
  OCMReject([_partialManagerMock launchWithTrigger:QONRequestTriggerIdentify completion:[OCMArg any]]);
  OCMReject([_mockRemoteConfigManager userHasBeenChanged]);
  OCMReject([_mockClient setUserID:[OCMArg any]]);

  // When
  [_partialManagerMock processIdentity:identityId];

  // Then
  OCMVerifyAll(_partialManagerMock);
  OCMVerifyAll(_mockRemoteConfigManager);
  OCMVerifyAll(_mockClient);
}

@end
