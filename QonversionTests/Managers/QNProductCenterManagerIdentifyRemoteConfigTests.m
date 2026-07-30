//
//  QNProductCenterManagerIdentifyRemoteConfigTests.m
//  QonversionTests
//
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>
#import "QNProductCenterManager.h"
#import "QNAPIClient.h"
#import "QNUserInfoService.h"
#import "QNIdentityManager.h"
#import "QNLocalStorage.h"
#import "QONFallbackService.h"
#import "QONRemoteConfigManager.h"

/*
 * Contract tests for the same-uid identify -> remote config cache
 * invalidation seam (DEV-1236 B4).
 *
 * The first identify for a user does not change the Qonversion uid (the
 * backend attaches the external identity to the existing client row), so the
 * destructive user-switch path never runs. Without an explicit invalidation
 * the host keeps the pre-login targeting evaluation for the rest of the
 * process lifetime. These tests pin:
 *   1. processIdentity resolving to the SAME uid invalidates the remote
 *      configs cache (and does NOT fire the destructive userHasBeenChanged);
 *   2. the invalidation runs BEFORE the pending-request replay — swapping the
 *      two lets the replay hit the still-warm cache, which serves the
 *      pre-identify evaluation and orphans queued completions;
 *   3. an identity error leaves the cache untouched.
 */

@interface QNProductCenterManager (IdentifyRemoteConfigTestPrivate)

@property (nonatomic, assign) BOOL launchingFinished;

- (void)processIdentity:(NSString *)identityId;

@end

@interface QNProductCenterManagerIdentifyRemoteConfigTests : XCTestCase

@property (nonatomic, strong) id mockClient;
@property (nonatomic, strong) id mockUserInfoService;
@property (nonatomic, strong) id mockIdentityManager;
@property (nonatomic, strong) id mockRemoteConfigManager;
@property (nonatomic, strong) QNProductCenterManager *manager;

@end

@implementation QNProductCenterManagerIdentifyRemoteConfigTests

- (void)setUp {
  [super setUp];

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

  _mockRemoteConfigManager = OCMClassMock([QONRemoteConfigManager class]);
  _manager.remoteConfigManager = _mockRemoteConfigManager;
}

- (void)tearDown {
  [_mockClient stopMocking];
  // Class mocks swizzle the class for as long as they live — stop them
  // explicitly so tests exercising the real classes in the same process
  // cannot be poisoned by ordering.
  [_mockIdentityManager stopMocking];
  [_mockRemoteConfigManager stopMocking];
  _manager = nil;

  [super tearDown];
}

- (void)testProcessIdentity_SameUid_InvalidatesRemoteConfigsCache {
  // Given - the backend resolves the identity to the CURRENT uid
  NSString *identityId = @"login@example.com";
  NSString *sameUid = @"uid_initial";
  OCMStub([_mockUserInfoService obtainUserID]).andReturn(sameUid);
  // Extra parens are required: without them the commas inside
  // invokeBlockWithArgs are parsed as extra OCMStub macro arguments.
  OCMStub(([_mockIdentityManager identify:identityId
                               completion:[OCMArg invokeBlockWithArgs:sameUid, [NSNull null], nil]]));

  // The destructive user-switch path must NOT fire on same-uid
  OCMReject([_mockRemoteConfigManager userHasBeenChanged]);

  // When - launchingFinished stays NO, so handlePendingRequests: returns
  // early and fireIdentitySuccess no-ops on the empty pending blocks
  [_manager processIdentity:identityId];

  // Then - deleting the invalidation call in the same-uid branch fails here
  OCMVerify([_mockRemoteConfigManager invalidateRemoteConfigsCache]);
  OCMVerifyAll(_mockRemoteConfigManager);
}

- (void)testProcessIdentity_SameUid_InvalidatesBeforePendingRequestReplay {
  // Given
  NSString *identityId = @"login@example.com";
  NSString *sameUid = @"uid_initial";
  OCMStub([_mockUserInfoService obtainUserID]).andReturn(sameUid);
  OCMStub(([_mockIdentityManager identify:identityId
                               completion:[OCMArg invokeBlockWithArgs:sameUid, [NSNull null], nil]]));

  // launchingFinished so PCM's handlePendingRequests: reaches the RC manager
  // (executeEntitlementsBlocksWithError: no-ops on zero queued blocks)
  _manager.launchingFinished = YES;

  NSMutableArray<NSString *> *order = [NSMutableArray new];
  OCMStub([_mockRemoteConfigManager invalidateRemoteConfigsCache]).andDo(^(NSInvocation *invocation) {
    [order addObject:@"invalidate"];
  });
  OCMStub([_mockRemoteConfigManager handlePendingRequests]).andDo(^(NSInvocation *invocation) {
    [order addObject:@"replay"];
  });

  // When
  [_manager processIdentity:identityId];

  // Then - the replay must observe an already-invalidated cache; the reversed
  // order serves queued completions the pre-identify evaluation and orphans
  // them on the cache-hit path
  XCTAssertEqualObjects(order, (@[@"invalidate", @"replay"]));
}

- (void)testProcessIdentity_IdentityError_DoesNotInvalidateRemoteConfigsCache {
  // Given - identify fails
  NSString *identityId = @"login@example.com";
  OCMStub([_mockUserInfoService obtainUserID]).andReturn(@"uid_initial");
  NSError *identityError = [NSError errorWithDomain:@"test" code:1 userInfo:nil];
  OCMStub(([_mockIdentityManager identify:identityId
                               completion:[OCMArg invokeBlockWithArgs:[NSNull null], identityError, nil]]));

  OCMReject([_mockRemoteConfigManager invalidateRemoteConfigsCache]);
  OCMReject([_mockRemoteConfigManager userHasBeenChanged]);

  // When
  [_manager processIdentity:identityId];

  // Then - the error is propagated to the RC manager without cache changes
  OCMVerify([_mockRemoteConfigManager userChangingRequestFailedWithError:identityError]);
  OCMVerifyAll(_mockRemoteConfigManager);
}

@end
