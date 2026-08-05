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
@property (nonatomic, assign) BOOL identityInProgress;
@property (nonatomic, strong) QONUser *user;
@property (nonatomic, strong) NSRecursiveLock *identityMutationLock;

- (void)processIdentity:(NSString *)identityId;
- (void)deliverIdentityRequest:(id)request error:(nullable NSError *)error;

@end

@interface QNProductCenterManagerIdentifyRemoteConfigTests : XCTestCase

@property (nonatomic, strong) id mockClient;
@property (nonatomic, strong) id mockUserInfoService;
@property (nonatomic, strong) id mockIdentityManager;
@property (nonatomic, strong) id mockRemoteConfigManager;
@property (nonatomic, strong) QNProductCenterManager *manager;

@end

@interface QNTrackingRecursiveLock : NSObject <NSLocking>

@property (nonatomic, strong) NSRecursiveLock *backingLock;
@property (nonatomic, strong) NSObject *metadataLock;
@property (nonatomic, strong, nullable) NSThread *ownerThread;
@property (nonatomic, assign) NSUInteger recursionDepth;

- (BOOL)isHeldByCurrentThread;

@end


@implementation QNTrackingRecursiveLock

- (instancetype)init {
  self = [super init];
  if (self) {
    _backingLock = [NSRecursiveLock new];
    _metadataLock = [NSObject new];
  }
  return self;
}

- (void)lock {
  [self.backingLock lock];
  @synchronized (self.metadataLock) {
    self.ownerThread = [NSThread currentThread];
    self.recursionDepth += 1;
  }
}

- (void)unlock {
  @synchronized (self.metadataLock) {
    NSAssert(self.ownerThread == [NSThread currentThread] && self.recursionDepth > 0,
             @"only the owning thread may unlock the identity mutation probe");
    self.recursionDepth -= 1;
    if (self.recursionDepth == 0) {
      self.ownerThread = nil;
    }
  }
  [self.backingLock unlock];
}

- (BOOL)isHeldByCurrentThread {
  @synchronized (self.metadataLock) {
    return self.ownerThread == [NSThread currentThread] && self.recursionDepth > 0;
  }
}

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
  OCMReject([_mockRemoteConfigManager userHasBeenChangedToUserID:[OCMArg any]]);

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

- (void)testProcessIdentity_SameUid_RemainsUnstableUntilRemoteConfigsAreInvalidated {
  NSString *identityId = @"login@example.com";
  NSString *sameUid = @"uid_initial";
  OCMStub([_mockUserInfoService obtainUserID]).andReturn(sameUid);
  OCMStub(([_mockIdentityManager identify:identityId
                               completion:[OCMArg invokeBlockWithArgs:sameUid, [NSNull null], nil]]));

  _manager.launchingFinished = YES;
  _manager.identityInProgress = YES;

  __block BOOL stableDuringInvalidation = YES;
  OCMStub([_mockRemoteConfigManager invalidateRemoteConfigsCache]).andDo(^(NSInvocation *invocation) {
    stableDuringInvalidation = [self.manager isUserStable];
  });

  [_manager processIdentity:identityId];

  XCTAssertFalse(stableDuringInvalidation,
                 @"a concurrent Remote Config request must not observe the old warm cache during identity completion");
  XCTAssertTrue([_manager isUserStable]);
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
  OCMReject([_mockRemoteConfigManager userHasBeenChangedToUserID:[OCMArg any]]);

  // When
  [_manager processIdentity:identityId];

  // Then - the error is propagated to the RC manager without cache changes
  OCMVerify([_mockRemoteConfigManager userChangingRequestFailedWithError:identityError]);
  OCMVerifyAll(_mockRemoteConfigManager);
}

- (void)testIdentifyRetryStartsFreshRemoteConfigIdentityWindow {
  NSString *identityId = @"login@example.com";
  NSError *identityError = [NSError errorWithDomain:@"test" code:2 userInfo:nil];
  _manager.launchingFinished = YES;
  OCMStub([_mockUserInfoService obtainCustomIdentityUserID]).andReturn(nil);
  OCMStub([_mockUserInfoService obtainUserID]).andReturn(@"uid_initial");
  __block NSUInteger remoteConfigAttemptStarts = 0;
  OCMStub([_mockRemoteConfigManager userChangingRequestStarted]).andDo(^(NSInvocation *invocation) {
    remoteConfigAttemptStarts += 1;
  });

  __block NSUInteger identityCalls = 0;
  OCMStub([_mockIdentityManager identify:identityId completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    identityCalls += 1;
    if (identityCalls == 1) {
      __unsafe_unretained QNIdentityCompletionHandler completion = nil;
      [invocation getArgument:&completion atIndex:3];
      completion(nil, identityError);
    }
  });

  [_manager identify:identityId completion:nil];
  [_manager identify:identityId completion:nil];

  XCTAssertEqual(identityCalls, 2);
  XCTAssertEqual(remoteConfigAttemptStarts, 2);
  OCMVerify([_mockRemoteConfigManager userChangingRequestFailedWithError:identityError]);
}

- (void)testPublicIdentifyPersistsMergedIdentityAfterAttemptOwnershipCheck {
  NSString *identityID = @"login@example.com";
  NSString *userID = @"uid_initial";
  _manager.launchingFinished = YES;
  OCMStub([_mockUserInfoService obtainCustomIdentityUserID]).andReturn(nil);
  OCMStub([_mockUserInfoService obtainUserID]).andReturn(userID);
  OCMExpect([_mockUserInfoService storeIdentity:userID]);
  OCMExpect([_mockUserInfoService storeCustomIdentityUserID:identityID]);
  OCMStub(([_mockIdentityManager identify:identityID
                               completion:[OCMArg invokeBlockWithArgs:userID, [NSNull null], nil]]));

  [_manager identify:identityID completion:nil];

  OCMVerify([_mockUserInfoService storeIdentity:userID]);
  OCMVerify([_mockUserInfoService storeCustomIdentityUserID:identityID]);
}

- (void)testOverlappingIdentifyCallsAreSerializedBeforeRemoteConfigAttemptStart {
  _manager.launchingFinished = YES;
  OCMStub([_mockUserInfoService obtainCustomIdentityUserID]).andReturn(nil);
  OCMStub([_mockUserInfoService obtainUserID]).andReturn(@"uid_initial");
  __block NSUInteger remoteConfigAttemptStarts = 0;
  OCMStub([_mockRemoteConfigManager userChangingRequestStarted]).andDo(^(NSInvocation *invocation) {
    remoteConfigAttemptStarts += 1;
  });
  __block NSMutableArray<QNIdentityCompletionHandler> *identityCompletions = [NSMutableArray new];
  OCMStub([_mockIdentityManager identify:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QNIdentityCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    [identityCompletions addObject:[completion copy]];
  });

  [_manager identify:@"first@example.com" completion:nil];
  [_manager identify:@"second@example.com" completion:nil];
  XCTAssertEqual(identityCompletions.count, 1, @"the second identity request must not overlap the active attempt");
  XCTAssertEqual(remoteConfigAttemptStarts, 1);

  NSError *firstError = [NSError errorWithDomain:@"identity" code:3 userInfo:nil];
  identityCompletions[0](nil, firstError);

  XCTAssertEqual(identityCompletions.count, 2, @"the queued identity must start after the first terminal result");
  XCTAssertEqual(remoteConfigAttemptStarts, 2);
  OCMVerify([_mockRemoteConfigManager userChangingRequestFailedWithError:firstError]);
}

- (void)testDuplicateActiveIdentitySharesFailureWithoutHiddenRetry {
  _manager.launchingFinished = YES;
  OCMStub([_mockUserInfoService obtainCustomIdentityUserID]).andReturn(nil);
  OCMStub([_mockUserInfoService obtainUserID]).andReturn(@"uid_initial");
  __block NSMutableArray<QNIdentityCompletionHandler> *identityCompletions = [NSMutableArray new];
  OCMStub([_mockIdentityManager identify:@"a@example.com" completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QNIdentityCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    [identityCompletions addObject:[completion copy]];
  });

  __block NSUInteger callbackCount = 0;
  [_manager identify:@"a@example.com" completion:^(QONUser * _Nullable user, NSError * _Nullable error) {
    callbackCount += 1;
    XCTAssertEqual(error.code, 77);
  }];
  [_manager identify:@"a@example.com" completion:^(QONUser * _Nullable user, NSError * _Nullable error) {
    callbackCount += 1;
    XCTAssertEqual(error.code, 77);
  }];

  XCTAssertEqual(identityCompletions.count, 1);
  NSError *failure = [NSError errorWithDomain:@"identity" code:77 userInfo:nil];
  identityCompletions.firstObject(nil, failure);

  XCTAssertEqual(identityCompletions.count, 1, @"an active duplicate must not be retried without a live caller");
  XCTAssertEqual(callbackCount, 2);
}

- (void)testSeparatedDuplicateIdentityPreservesFIFOOrder {
  _manager.launchingFinished = YES;
  OCMStub([_mockUserInfoService obtainCustomIdentityUserID]).andReturn(nil);
  OCMStub([_mockUserInfoService obtainUserID]).andReturn(@"uid_initial");
  __block NSMutableArray<NSString *> *startedIdentityIDs = [NSMutableArray new];
  __block NSMutableArray<QNIdentityCompletionHandler> *identityCompletions = [NSMutableArray new];
  OCMStub([_mockIdentityManager identify:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained NSString *identityID = nil;
    __unsafe_unretained QNIdentityCompletionHandler completion = nil;
    [invocation getArgument:&identityID atIndex:2];
    [invocation getArgument:&completion atIndex:3];
    [startedIdentityIDs addObject:[identityID copy]];
    [identityCompletions addObject:[completion copy]];
  });

  [_manager identify:@"a@example.com" completion:nil];
  [_manager identify:@"b@example.com" completion:nil];
  [_manager identify:@"a@example.com" completion:nil];
  XCTAssertEqualObjects(startedIdentityIDs, (@[@"a@example.com"]));

  identityCompletions[0](@"uid_initial", nil);
  XCTAssertEqualObjects(startedIdentityIDs, (@[@"a@example.com", @"b@example.com"]));
  identityCompletions[1](@"uid_initial", nil);
  XCTAssertEqualObjects(startedIdentityIDs, (@[@"a@example.com", @"b@example.com", @"a@example.com"]));
  identityCompletions[2](@"uid_initial", nil);
  XCTAssertFalse(_manager.identityInProgress);
}

- (void)testQueuedSeparatedDuplicateIsNotGloballyDeduplicated {
  _manager.launchingFinished = YES;
  OCMStub([_mockUserInfoService obtainCustomIdentityUserID]).andReturn(nil);
  OCMStub([_mockUserInfoService obtainUserID]).andReturn(@"uid_initial");
  __block NSMutableArray<NSString *> *startedIdentityIDs = [NSMutableArray new];
  __block NSMutableArray<QNIdentityCompletionHandler> *identityCompletions = [NSMutableArray new];
  OCMStub([_mockIdentityManager identify:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained NSString *identityID = nil;
    __unsafe_unretained QNIdentityCompletionHandler completion = nil;
    [invocation getArgument:&identityID atIndex:2];
    [invocation getArgument:&completion atIndex:3];
    [startedIdentityIDs addObject:[identityID copy]];
    [identityCompletions addObject:[completion copy]];
  });

  [_manager identify:@"a@example.com" completion:nil];
  [_manager identify:@"b@example.com" completion:nil];
  [_manager identify:@"c@example.com" completion:nil];
  [_manager identify:@"b@example.com" completion:nil];

  identityCompletions[0](@"uid_initial", nil);
  identityCompletions[1](@"uid_initial", nil);
  identityCompletions[2](@"uid_initial", nil);
  identityCompletions[3](@"uid_initial", nil);
  XCTAssertEqualObjects(startedIdentityIDs,
                        (@[@"a@example.com", @"b@example.com", @"c@example.com", @"b@example.com"]));
}

- (void)testLogoutCancelsActiveAndQueuedIdentityCompletionsAndIgnoresLateResponse {
  _manager.launchingFinished = YES;
  OCMStub([_mockUserInfoService obtainCustomIdentityUserID]).andReturn(nil);
  OCMStub([_mockUserInfoService obtainUserID]).andReturn(@"uid_initial");
  OCMStub([_mockIdentityManager logoutIfNeeded]).andReturn(NO);
  __block QNIdentityCompletionHandler activeCompletion = nil;
  OCMStub([_mockIdentityManager identify:@"a@example.com" completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QNIdentityCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    activeCompletion = [completion copy];
  });
  OCMReject([_mockUserInfoService storeCustomIdentityUserID:@"a@example.com"]);
  OCMReject([_mockUserInfoService storeIdentity:[OCMArg any]]);

  __block NSUInteger cancelledCallbacks = 0;
  QONUserInfoCompletionHandler callback = ^(QONUser * _Nullable user, NSError * _Nullable error) {
    XCTAssertEqualObjects(error.domain, NSURLErrorDomain);
    XCTAssertEqual(error.code, NSURLErrorCancelled);
    cancelledCallbacks += 1;
  };
  [_manager identify:@"a@example.com" completion:callback];
  [_manager identify:@"b@example.com" completion:callback];

  [_manager logout];
  XCTAssertEqual(cancelledCallbacks, 2);
  activeCompletion(@"uid_initial", nil);
  XCTAssertEqual(cancelledCallbacks, 2);
  XCTAssertTrue([_manager isUserStable]);
}

- (void)testLogoutCancelsPendingOnlyIdentityAndRemoteConfigWaiters {
  _manager.launchingFinished = NO;
  OCMStub([_mockIdentityManager logoutIfNeeded]).andReturn(NO);
  __block NSError *callbackError = nil;
  OCMExpect([_mockRemoteConfigManager userChangingRequestFailedWithError:[OCMArg checkWithBlock:^BOOL(NSError *error) {
    return error.code == NSURLErrorCancelled;
  }]]);

  [_manager identify:@"queued@example.com" completion:^(QONUser * _Nullable user, NSError * _Nullable error) {
    callbackError = error;
  }];
  [_manager logout];

  XCTAssertEqual(callbackError.code, NSURLErrorCancelled);
  OCMVerifyAll(_mockRemoteConfigManager);
}

- (void)testLogoutDrainsCancelledRemoteConfigWindowBeforePublishingOriginalUserScope {
  _manager.launchingFinished = YES;
  OCMStub([_mockUserInfoService obtainCustomIdentityUserID]).andReturn(nil);
  OCMStub([_mockUserInfoService obtainUserID]).andReturn(@"uid_initial");
  OCMStub([_mockIdentityManager logoutIfNeeded]).andReturn(YES);
  OCMStub([_mockIdentityManager identify:[OCMArg any] completion:[OCMArg any]]);

  NSMutableArray<NSString *> *order = [NSMutableArray new];
  OCMStub([_mockRemoteConfigManager userChangingRequestFailedWithError:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    [order addObject:@"cancel-old-window"];
  });
  OCMStub([_mockRemoteConfigManager userHasBeenChangedToUserID:@"uid_initial"]).andDo(^(NSInvocation *invocation) {
    [order addObject:@"publish-original-scope"];
  });

  [_manager identify:@"active@example.com" completion:nil];
  [_manager logout];

  XCTAssertEqualObjects(order, (@[@"cancel-old-window", @"publish-original-scope"]),
                        @"the successful logout scope must clear the cancellation latch last");
}

- (void)testLogoutKeepsRemoteConfigCancellationInsideIdentityMutationBoundary {
  _manager.launchingFinished = YES;
  OCMStub([_mockUserInfoService obtainCustomIdentityUserID]).andReturn(nil);
  OCMStub([_mockUserInfoService obtainUserID]).andReturn(@"uid_initial");
  OCMStub([_mockIdentityManager logoutIfNeeded]).andReturn(NO);

  dispatch_semaphore_t firstIdentityStarted = dispatch_semaphore_create(0);
  dispatch_semaphore_t secondIdentityStarted = dispatch_semaphore_create(0);
  dispatch_semaphore_t cancellationEntered = dispatch_semaphore_create(0);
  dispatch_semaphore_t releaseCancellation = dispatch_semaphore_create(0);
  dispatch_semaphore_t logoutFinished = dispatch_semaphore_create(0);
  __block NSUInteger identityCallCount = 0;
  __block QNIdentityCompletionHandler secondIdentityCompletion = nil;
  OCMStub([_mockIdentityManager identify:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QNIdentityCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    @synchronized (self) {
      identityCallCount += 1;
      if (identityCallCount == 1) {
        dispatch_semaphore_signal(firstIdentityStarted);
      } else {
        secondIdentityCompletion = [completion copy];
        dispatch_semaphore_signal(secondIdentityStarted);
      }
    }
  });

  __block BOOL blockFirstCancellation = YES;
  OCMStub([_mockRemoteConfigManager userChangingRequestFailedWithError:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    if (blockFirstCancellation) {
      dispatch_semaphore_signal(cancellationEntered);
      dispatch_semaphore_wait(releaseCancellation, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC));
    }
  });

  [_manager identify:@"active@example.com" completion:nil];
  XCTAssertEqual(dispatch_semaphore_wait(firstIdentityStarted, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    [self.manager logout];
    dispatch_semaphore_signal(logoutFinished);
  });
  XCTAssertEqual(dispatch_semaphore_wait(cancellationEntered, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    [self.manager identify:@"new@example.com" completion:nil];
  });
  long prematureStart = dispatch_semaphore_wait(secondIdentityStarted,
                                                  dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC));
  XCTAssertNotEqual(prematureStart, 0,
                    @"a new identify must not start while logout is still draining the old RC window");

  blockFirstCancellation = NO;
  dispatch_semaphore_signal(releaseCancellation);
  XCTAssertEqual(dispatch_semaphore_wait(logoutFinished, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
  if (prematureStart != 0) {
    XCTAssertEqual(dispatch_semaphore_wait(secondIdentityStarted, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
  }

  NSError *cleanupError = [NSError errorWithDomain:@"test" code:901 userInfo:nil];
  secondIdentityCompletion(nil, cleanupError);
}

- (void)testSameUIDTerminalCommitRemainsInsideIdentityMutationBoundary {
  _manager.launchingFinished = YES;
  OCMStub([_mockUserInfoService obtainCustomIdentityUserID]).andReturn(nil);
  OCMStub([_mockUserInfoService obtainUserID]).andReturn(@"uid_initial");
  OCMStub(([_mockIdentityManager identify:@"same@example.com"
                               completion:[OCMArg invokeBlockWithArgs:@"uid_initial", [NSNull null], nil]]));

  QNTrackingRecursiveLock *mutationLock = [QNTrackingRecursiveLock new];
  _manager.identityMutationLock = (NSRecursiveLock *)mutationLock;
  __block BOOL lockHeldDuringTerminalCommit = NO;
  id partialManager = OCMPartialMock(_manager);
  OCMStub([partialManager deliverIdentityRequest:[OCMArg any] error:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    lockHeldDuringTerminalCommit = [mutationLock isHeldByCurrentThread];
  });

  [_manager identify:@"same@example.com" completion:nil];

  XCTAssertTrue(lockHeldDuringTerminalCommit,
                @"logout must not overtake a same-UID identify terminal commit");
  [partialManager stopMocking];
}

- (void)testUserInfoSnapshotsIdentityBeforeDispatchingCompletionToMain {
  _manager.launchingFinished = YES;
  OCMStub([_mockUserInfoService obtainUserID]).andReturn(@"uid-a");
  OCMStub([_mockUserInfoService obtainCustomIdentityUserID]).andReturn(@"a@example.com");
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"user info completion"];
  dispatch_semaphore_t scheduled = dispatch_semaphore_create(0);
  __block QONUser *expectedUser = nil;
  __block QONUser *deliveredUser = nil;

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    [self.manager userInfo:^(QONUser * _Nullable user, NSError * _Nullable error) {
      deliveredUser = user;
      [completionExpectation fulfill];
    }];
    expectedUser = self.manager.user;
    dispatch_semaphore_signal(scheduled);
  });
  XCTAssertEqual(dispatch_semaphore_wait(scheduled, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
  _manager.user = [QONUser new];

  [self waitForExpectationsWithTimeout:1 handler:nil];
  XCTAssertEqual(deliveredUser, expectedUser);
}

- (void)testConcurrentIdentifyCallsStartOnlyOneNetworkAttempt {
  _manager.launchingFinished = YES;
  OCMStub([_mockUserInfoService obtainCustomIdentityUserID]).andReturn(nil);
  OCMStub([_mockUserInfoService obtainUserID]).andReturn(@"uid_initial");
  OCMStub([_mockIdentityManager logoutIfNeeded]).andReturn(NO);
  __block NSUInteger identityCalls = 0;
  OCMStub([_mockIdentityManager identify:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    @synchronized (self) {
      identityCalls += 1;
    }
  });

  dispatch_group_t group = dispatch_group_create();
  dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
  for (NSUInteger index = 0; index < 24; index++) {
    dispatch_group_async(group, queue, ^{
      [self.manager identify:[NSString stringWithFormat:@"user-%lu@example.com", (unsigned long)index] completion:nil];
    });
  }
  XCTAssertEqual(dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)), 0);
  @synchronized (self) {
    XCTAssertEqual(identityCalls, 1, @"the identity lock must make simultaneous callers share one active slot");
  }
  [_manager logout];
}

@end
