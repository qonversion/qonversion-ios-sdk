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
 * Contract tests for -[QNProductCenterManager processIdentity:].
 *
 * NOTE: these tests pin the behaviour of the host-driven
 * `Qonversion.identify(userID:)` path only. They are NOT part of the Web 2 App
 * redemption flow: under grant-first the backend grants the entitlement
 * server-side and the SDK's redemption success path does NOT call
 * identify/merge — it triggers an entitlements refresh
 * (launchWithTrigger:QONRequestTriggerActualizePermissions, see
 * QONRedemptionManager.m). An earlier version of this comment claimed the
 * /v4/web/redeem/status recovery UX "relies on identify"; that rationale was
 * stale and has been removed to avoid misleading integrators into adding a
 * redundant identify call.
 *
 * What these tests still legitimately guard: when a host app calls
 * `identify(userID:)` and the merged Qonversion uid CHANGES
 * (QNProductCenterManager.m), the manager must call
 * `resetActualPermissionsCache` THEN `launchWithTrigger:QONRequestTriggerIdentify`
 * so the freshly-identified user's entitlements are fetched. If a future change
 * defers or skips the launch step, identify-based user switching silently
 * breaks — these tests fail CI in that case.
 *
 * Source of truth: -[QNProductCenterManager processIdentity:].
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
