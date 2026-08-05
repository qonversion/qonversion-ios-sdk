#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>
#import "QNProductCenterManager.h"
#import "QNAPIClient.h"
#import "QNUserDefaultsStorage.h"
#import "QNStoreKitService.h"
#import "QNTestConstants.h"
#import "QONLaunchResult.h"
#import "QONLaunchResult+Protected.h"
#import "QNUserInfoService.h"
#import "QNIdentityManager.h"
#import "QNLocalStorage.h"
#import "QONFallbackService.h"
#import "QONRemoteConfigManager.h"
#import "QONRequestTrigger.h"
#import "Helpers/XCTestCase+TestJSON.h"

@interface QNProductCenterManager (RestoreTestPrivate)

@property (nonatomic) QNStoreKitService *storeKitService;
@property (nonatomic) QNUserDefaultsStorage *persistentStorage;
@property (nonatomic) QNAPIClient *apiClient;
@property (nonatomic) QONLaunchResult *launchResult;
@property (nonatomic) NSError *launchError;
@property (nonatomic) QONUser *user;
@property (nonatomic, assign) BOOL launchingFinished;
@property (nonatomic, assign) BOOL receiptRestoreInProgress;
@property (nonatomic, assign) BOOL restoreInProgress;
@property (nonatomic, assign) BOOL awaitingRestoreResult;
@property (nonatomic, assign) BOOL unhandledLogoutAvailable;
@property (nonatomic, strong) NSRecursiveLock *identityMutationLock;

- (void)handleUserSwitchIfNeededWithResult:(QONLaunchResult *)result;
- (void)restoreReceipt:(QNRestoreCompletionHandler)completion;
- (void)restoreTransactions:(QNRestoreCompletionHandler)completion;
- (void)handleRestoreCompletedTransactionsFinished;
- (void)actualizeEntitlements:(QONEntitlementsCompletionHandler)completion;

@end

@interface ProductCenterManagerRestoreUserSwitchTests : XCTestCase

@property (nonatomic, strong) id mockClient;
@property (nonatomic, strong) id mockUserInfoService;
@property (nonatomic, strong) id mockIdentityManager;
@property (nonatomic, strong) id mockRemoteConfigManager;
@property (nonatomic, strong) id mockStoreKitService;
@property (nonatomic, strong) QNProductCenterManager *manager;

@end

@interface QNRestoreTrackingRecursiveLock : NSObject <NSLocking>

@property (nonatomic, strong) NSRecursiveLock *backingLock;
@property (nonatomic, strong) NSObject *metadataLock;
@property (nonatomic, strong, nullable) NSThread *ownerThread;
@property (nonatomic, assign) NSUInteger recursionDepth;

- (BOOL)isHeldByCurrentThread;

@end

@implementation QNRestoreTrackingRecursiveLock

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

@implementation ProductCenterManagerRestoreUserSwitchTests

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

  _mockStoreKitService = OCMClassMock([QNStoreKitService class]);
  _manager.storeKitService = _mockStoreKitService;
  
  _mockRemoteConfigManager = OCMClassMock([QONRemoteConfigManager class]);
  _manager.remoteConfigManager = _mockRemoteConfigManager;
}

- (void)tearDown {
  [_mockClient stopMocking];
  [_mockIdentityManager stopMocking];
  [_mockStoreKitService stopMocking];
  [_mockRemoteConfigManager stopMocking];
  _manager = nil;
}

#pragma mark - handleUserSwitchIfNeededWithResult: Tests

- (void)testHandleUserSwitch_SameUid_NoSwitch {
  // Given
  NSString *currentUserId = @"user_123";
  OCMStub([_mockUserInfoService obtainUserID]).andReturn(currentUserId);
  
  QONLaunchResult *launchResult = [[QONLaunchResult alloc] init];
  launchResult.uid = currentUserId;
  
  // Set up reject expectations before the action
  OCMReject([_mockUserInfoService storeIdentity:[OCMArg any]]);
  OCMReject([_mockRemoteConfigManager userHasBeenChanged]);
  OCMReject([_mockRemoteConfigManager userHasBeenChangedToUserID:[OCMArg any]]);
  
  // When
  [_manager handleUserSwitchIfNeededWithResult:launchResult];
  
  // Then - if rejected calls were made, the test would have failed already
  OCMVerifyAll(_mockUserInfoService);
  OCMVerifyAll(_mockRemoteConfigManager);
}

- (void)testHandleUserSwitch_DifferentUid_SwitchOccurs {
  // Given
  NSString *currentUserId = @"user_new";
  NSString *originalUserId = @"user_old";
  OCMStub([_mockUserInfoService obtainUserID]).andReturn(currentUserId);
  
  QONLaunchResult *launchResult = [[QONLaunchResult alloc] init];
  launchResult.uid = originalUserId;
  
  // When
  [_manager handleUserSwitchIfNeededWithResult:launchResult];
  
  // Then
  OCMVerify([_mockUserInfoService storeIdentity:originalUserId]);
  OCMVerify([_mockRemoteConfigManager userHasBeenChangedToUserID:originalUserId]);
  OCMReject([_mockClient setUserID:[OCMArg any]]);
}

- (void)testHandleUserSwitch_CommitsStorageAndRemoteConfigScopeInsideMutationBoundary {
  OCMStub([_mockUserInfoService obtainUserID]).andReturn(@"user_old");
  QONLaunchResult *launchResult = [[QONLaunchResult alloc] init];
  launchResult.uid = @"user_new";

  QNRestoreTrackingRecursiveLock *mutationLock = [QNRestoreTrackingRecursiveLock new];
  _manager.identityMutationLock = (NSRecursiveLock *)mutationLock;
  __block BOOL scopePublishedInsideMutationBoundary = NO;
  OCMStub([_mockRemoteConfigManager userHasBeenChangedToUserID:@"user_new"]).andDo(^(NSInvocation *invocation) {
    scopePublishedInsideMutationBoundary = [mutationLock isHeldByCurrentThread];
  });

  [_manager handleUserSwitchIfNeededWithResult:launchResult];

  XCTAssertTrue(scopePublishedInsideMutationBoundary,
                @"storage and Remote Config scope must commit under one identity boundary");
}

- (void)testRestoreReceiptStartedBeforeLogoutCannotApplyLateUserScope {
  OCMStub([_mockUserInfoService obtainUserID]).andReturn(@"user_initial");
  OCMStub([_mockIdentityManager logoutIfNeeded]).andReturn(NO);

  __block void (^launchCompletion)(NSDictionary * _Nullable, NSError * _Nullable) = nil;
  OCMStub([_mockStoreKitService receipt:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained void (^receiptCompletion)(NSString *) = nil;
    [invocation getArgument:&receiptCompletion atIndex:2];
    receiptCompletion(@"receipt");
  });
  OCMStub([_mockClient launchRequest:QONRequestTriggerRestore completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained void (^completion)(NSDictionary * _Nullable, NSError * _Nullable) = nil;
    [invocation getArgument:&completion atIndex:3];
    launchCompletion = [completion copy];
  });

  __block BOOL storedLateUser = NO;
  __block BOOL publishedLateScope = NO;
  OCMStub([_mockUserInfoService storeIdentity:@"qonversion_user_id"]).andDo(^(NSInvocation *invocation) {
    storedLateUser = YES;
  });
  OCMStub([_mockRemoteConfigManager userHasBeenChangedToUserID:@"qonversion_user_id"]).andDo(^(NSInvocation *invocation) {
    publishedLateScope = YES;
  });

  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"stale restore completes"];
  __block NSError *restoreError = nil;
  [_manager restoreReceipt:^(NSDictionary<NSString *, QONEntitlement *> *entitlements, NSError *error) {
    restoreError = error;
    [completionExpectation fulfill];
  }];
  XCTAssertNotNil(launchCompletion);

  [_manager logout];
  NSDictionary *response = [self JSONObjectFromContentsOfFile:keyQNInitFullSuccessJSON];
  launchCompletion(response, nil);

  [self waitForExpectationsWithTimeout:keyQNTestTimeout handler:nil];
  XCTAssertFalse(storedLateUser, @"a restore older than logout must not rewrite identity storage");
  XCTAssertFalse(publishedLateScope, @"a restore older than logout must not publish its Remote Config scope");
  XCTAssertNotEqualObjects(_manager.launchResult.uid, @"qonversion_user_id");
  XCTAssertEqual(restoreError.code, NSURLErrorCancelled);
}

- (void)testRestoreTransactionsStartedBeforeLogoutCannotApplyLateUserScope {
  OCMStub([_mockUserInfoService obtainUserID]).andReturn(@"user_initial");
  OCMStub([_mockIdentityManager logoutIfNeeded]).andReturn(NO);

  __block void (^launchCompletion)(NSDictionary * _Nullable, NSError * _Nullable) = nil;
  OCMStub([_mockClient launchRequest:QONRequestTriggerSyncHistoricalData completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained void (^completion)(NSDictionary * _Nullable, NSError * _Nullable) = nil;
    [invocation getArgument:&completion atIndex:3];
    launchCompletion = [completion copy];
  });

  __block BOOL storedLateUser = NO;
  __block BOOL publishedLateScope = NO;
  OCMStub([_mockUserInfoService storeIdentity:@"qonversion_user_id"]).andDo(^(NSInvocation *invocation) {
    storedLateUser = YES;
  });
  OCMStub([_mockRemoteConfigManager userHasBeenChangedToUserID:@"qonversion_user_id"]).andDo(^(NSInvocation *invocation) {
    publishedLateScope = YES;
  });

  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"stale transaction restore completes"];
  __block NSError *restoreError = nil;
  [_manager restoreTransactions:^(NSDictionary<NSString *, QONEntitlement *> *entitlements, NSError *error) {
    restoreError = error;
    [completionExpectation fulfill];
  }];
  [_manager handleRestoreCompletedTransactionsFinished];
  XCTAssertNotNil(launchCompletion);

  [_manager logout];
  NSDictionary *response = [self JSONObjectFromContentsOfFile:keyQNInitFullSuccessJSON];
  launchCompletion(response, nil);

  [self waitForExpectationsWithTimeout:keyQNTestTimeout handler:nil];
  XCTAssertFalse(storedLateUser, @"a transaction restore older than logout must not rewrite identity storage");
  XCTAssertFalse(publishedLateScope, @"a transaction restore older than logout must not publish its Remote Config scope");
  XCTAssertNotEqualObjects(_manager.launchResult.uid, @"qonversion_user_id");
  XCTAssertEqual(restoreError.code, NSURLErrorCancelled);
}

- (void)testOrdinaryLaunchResponseCannotOverwriteNewerRestoreScopeState {
  OCMStub([_mockUserInfoService obtainUserID]).andReturn(@"user_initial");
  __block void (^launchCompletion)(NSDictionary * _Nullable, NSError * _Nullable) = nil;
  OCMStub([_mockClient launchRequest:QONRequestTriggerActualizePermissions completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained void (^completion)(NSDictionary * _Nullable, NSError * _Nullable) = nil;
    [invocation getArgument:&completion atIndex:3];
    launchCompletion = [completion copy];
  });

  QONUser *sentinelUser = (QONUser *)[NSObject new];
  _manager.user = sentinelUser;
  __block NSError *launchError = nil;
  [_manager launch:QONRequestTriggerActualizePermissions completion:^(QONLaunchResult *result, NSError *error) {
    launchError = error;
  }];
  XCTAssertNotNil(launchCompletion);

  QONLaunchResult *restoreResult = [[QONLaunchResult alloc] init];
  restoreResult.uid = @"restored_user";
  [_manager handleUserSwitchIfNeededWithResult:restoreResult];

  NSDictionary *oldScopeResponse = [self JSONObjectFromContentsOfFile:keyQNInitFullSuccessJSON];
  launchCompletion(oldScopeResponse, nil);

  XCTAssertEqual(_manager.user, sentinelUser,
                 @"an old ordinary launch must be rejected before mapper state is written");
  XCTAssertEqual(launchError.code, NSURLErrorCancelled);
}

- (void)testStaleActualizeResponseCannotDisarmPendingLogoutRefresh {
  OCMStub([_mockUserInfoService obtainUserID]).andReturn(@"user_initial");
  OCMStub([_mockIdentityManager logoutIfNeeded]).andReturn(YES);
  NSDictionary *response = [self JSONObjectFromContentsOfFile:keyQNInitFullSuccessJSON];

  __block void (^actualizeResponse)(NSDictionary * _Nullable, NSError * _Nullable) = nil;
  OCMStub([_mockClient launchRequest:QONRequestTriggerActualizePermissions completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained void (^completion)(NSDictionary * _Nullable, NSError * _Nullable) = nil;
    [invocation getArgument:&completion atIndex:3];
    actualizeResponse = [completion copy];
  });
  __block BOOL logoutRefreshStarted = NO;
  OCMStub([_mockClient launchRequest:QONRequestTriggerLogout completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    logoutRefreshStarted = YES;
    __unsafe_unretained void (^completion)(NSDictionary * _Nullable, NSError * _Nullable) = nil;
    [invocation getArgument:&completion atIndex:3];
    completion(response, nil);
  });

  XCTestExpectation *actualizeExpectation = [self expectationWithDescription:@"stale actualize completes"];
  __block NSError *actualizeError = nil;
  [_manager actualizeEntitlements:^(NSDictionary<NSString *, QONEntitlement *> *entitlements, NSError *error) {
    actualizeError = error;
    [actualizeExpectation fulfill];
  }];
  XCTAssertNotNil(actualizeResponse);

  [_manager logout];
  XCTAssertTrue(_manager.unhandledLogoutAvailable);
  actualizeResponse(response, nil);

  [self waitForExpectationsWithTimeout:keyQNTestTimeout handler:nil];
  XCTAssertEqual(actualizeError.code, NSURLErrorCancelled);
  XCTAssertTrue(logoutRefreshStarted,
                @"the stale actualize callback must not clear the pending logout refresh");
  XCTAssertFalse(_manager.unhandledLogoutAvailable);
}

- (void)testHandleUserSwitch_NilResult_NoSwitch {
  // Given - set up reject expectations before the action
  OCMReject([_mockUserInfoService storeIdentity:[OCMArg any]]);
  OCMReject([_mockRemoteConfigManager userHasBeenChanged]);
  OCMReject([_mockRemoteConfigManager userHasBeenChangedToUserID:[OCMArg any]]);
  
  // When
  [_manager handleUserSwitchIfNeededWithResult:nil];
  
  // Then
  OCMVerifyAll(_mockUserInfoService);
  OCMVerifyAll(_mockRemoteConfigManager);
}

- (void)testHandleUserSwitch_EmptyUid_NoSwitch {
  // Given
  QONLaunchResult *launchResult = [[QONLaunchResult alloc] init];
  launchResult.uid = @"";
  
  // Set up reject expectations before the action
  OCMReject([_mockUserInfoService storeIdentity:[OCMArg any]]);
  OCMReject([_mockRemoteConfigManager userHasBeenChanged]);
  OCMReject([_mockRemoteConfigManager userHasBeenChangedToUserID:[OCMArg any]]);
  
  // When
  [_manager handleUserSwitchIfNeededWithResult:launchResult];
  
  // Then
  OCMVerifyAll(_mockUserInfoService);
  OCMVerifyAll(_mockRemoteConfigManager);
}

@end
