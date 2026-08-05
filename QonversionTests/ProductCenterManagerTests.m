#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>
#import "QNProductCenterManager.h"
#import "QNAPIClient.h"
#import "QNUserDefaultsStorage.h"
#import "QNStoreKitService.h"
#import "QNTestConstants.h"
#import "QONLaunchResult.h"
#import "QNUserInfoService.h"
#import "QNIdentityManager.h"
#import "QNLocalStorage.h"
#import "QONFallbackService.h"
#import "Helpers/XCTestCase+TestJSON.h"
#import "QONRequestTrigger.h"

@interface QNProductCenterManager (Private)

@property (nonatomic) QNStoreKitService *storeKitService;
@property (nonatomic) QNUserDefaultsStorage *persistentStorage;

@property (nonatomic) QONPurchaseCompletionHandler purchasingBlock;

@property (nonatomic, copy) NSMutableArray *entitlementsBlocks;
@property (nonatomic, copy) NSMutableArray *productsBlocks;
@property (nonatomic, copy) NSMutableArray *userInfoBlocks;
@property (nonatomic) QNAPIClient *apiClient;

@property (nonatomic) QONLaunchResult *launchResult;
@property (nonatomic) NSError *launchError;

@property (nonatomic, assign) BOOL launchingFinished;
@property (nonatomic, assign) BOOL productsLoaded;
@property (nonatomic, strong) NSRecursiveLock *identityMutationLock;

- (void)checkEntitlements:(QONEntitlementsCompletionHandler)result;
- (void)actualizeEntitlements:(QONEntitlementsCompletionHandler)completion;
- (void)executeUserBlocks;

@end

@interface QNLockOrderArray : NSMutableArray

@property (nonatomic, strong) NSMutableArray *storage;
@property (nonatomic) dispatch_semaphore_t objectAdded;

@end

@implementation QNLockOrderArray

- (instancetype)initWithObjectAddedSemaphore:(dispatch_semaphore_t)objectAdded {
  self = [super init];
  if (self) {
    _storage = [NSMutableArray new];
    _objectAdded = objectAdded;
  }
  return self;
}

- (NSUInteger)count {
  return self.storage.count;
}

- (id)objectAtIndex:(NSUInteger)index {
  return self.storage[index];
}

- (void)insertObject:(id)anObject atIndex:(NSUInteger)index {
  [self.storage insertObject:anObject atIndex:index];
  dispatch_semaphore_signal(self.objectAdded);
}

- (void)removeObjectAtIndex:(NSUInteger)index {
  [self.storage removeObjectAtIndex:index];
}

- (id)copyWithZone:(NSZone *)zone {
  return self;
}

@end

@interface ProductCenterManagerTests : XCTestCase

@property (nonatomic) id mockClient;
@property (nonatomic) QNProductCenterManager *manager;

@end

@implementation ProductCenterManagerTests

- (void)setUp {
  _mockClient = OCMClassMock([QNAPIClient class]);
  id mockUserInfoService = OCMClassMock([QNUserInfoService class]);
  id mockIdentityManager = OCMClassMock([QNIdentityManager class]);
  id mockLocalStorage = OCMProtocolMock(@protocol(QNLocalStorage));
  id mockFallbackService = OCMClassMock([QONFallbackService class]);
  _manager = [[QNProductCenterManager alloc] initWithUserInfoService:mockUserInfoService identityManager:mockIdentityManager localStorage:mockLocalStorage fallbackService:mockFallbackService];
  [_manager setApiClient:_mockClient];
}

- (void)tearDown {
  _manager = nil;
}

- (void)testThatProductCenterGetLaunchModel {
  XCTestExpectation *expectation = [self expectationWithDescription:@""];
  
  OCMStub([_mockClient launchRequest:QONRequestTriggerInit completion:([OCMArg invokeBlockWithArgs:[self JSONObjectFromContentsOfFile:keyQNInitFullSuccessJSON], [NSNull null], nil])]);
  
  [_manager launch:QONRequestTriggerInit completion:^(QONLaunchResult * _Nullable result, NSError * _Nullable error) {
    XCTAssertNotNil(result);
    XCTAssertNil(error);
    XCTAssertEqual(result.entitlements.count, 2);
    XCTAssertEqual(result.products.count, 1);
    XCTAssertEqualObjects(result.uid, @"qonversion_user_id");
    
    [expectation fulfill];
  }];

  [self waitForExpectationsWithTimeout:keyQNTestTimeout handler:nil];
}

- (void)testLaunchingFinishedWaitsForEveryConcurrentLaunchTicket {
  __block void (^firstResponse)(NSDictionary * _Nullable, NSError * _Nullable) = nil;
  __block void (^secondResponse)(NSDictionary * _Nullable, NSError * _Nullable) = nil;
  OCMStub([_mockClient launchRequest:QONRequestTriggerInit completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained void (^completion)(NSDictionary * _Nullable, NSError * _Nullable) = nil;
    [invocation getArgument:&completion atIndex:3];
    firstResponse = [completion copy];
  });
  OCMStub([_mockClient launchRequest:QONRequestTriggerProducts completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained void (^completion)(NSDictionary * _Nullable, NSError * _Nullable) = nil;
    [invocation getArgument:&completion atIndex:3];
    secondResponse = [completion copy];
  });

  [_manager launch:QONRequestTriggerInit completion:^(QONLaunchResult *result, NSError *error) {}];
  [_manager launch:QONRequestTriggerProducts completion:^(QONLaunchResult *result, NSError *error) {}];
  XCTAssertFalse(_manager.launchingFinished);

  NSDictionary *response = [self JSONObjectFromContentsOfFile:keyQNInitFullSuccessJSON];
  firstResponse(response, nil);
  XCTAssertFalse(_manager.launchingFinished,
                 @"one response must not make the manager stable while another launch is in flight");

  secondResponse(response, nil);
  XCTAssertTrue(_manager.launchingFinished);
}

- (void)testThatCheckPermissionStoreBlocksWhenLaunchingIsActive {
  // Given
  
  // When
  [_manager checkEntitlements:^(NSDictionary<NSString *,QONEntitlement *> * _Nonnull result, NSError * _Nullable error) {
    
  }];
  
  // Then
  XCTAssertEqual(_manager.entitlementsBlocks.count, 1);
}

- (void)testThatCheckPermissionCallBlockWhenLaunchingFinished {
  // Given
  _manager.launchingFinished = YES;
  XCTestExpectation *expectation = [self expectationWithDescription:@""];

  // When
  [_manager checkEntitlements:^(NSDictionary<NSString *,QONEntitlement *> * _Nonnull result, NSError * _Nullable error) {
    XCTAssertEqual(result, [NSDictionary new]);
    XCTAssertNil(error);
    XCTAssertEqual([NSThread mainThread], [NSThread currentThread]);

    [expectation fulfill];
  }];

  // Then
  [self waitForExpectationsWithTimeout:keyQNTestTimeout handler:nil];
}

- (void)testCheckEntitlementsDoesNotInvertIdentityAndCallbackLocks {
  dispatch_semaphore_t mutationLockHeld = dispatch_semaphore_create(0);
  dispatch_semaphore_t objectAdded = dispatch_semaphore_create(0);
  dispatch_semaphore_t checkFinished = dispatch_semaphore_create(0);
  dispatch_semaphore_t unlockFinished = dispatch_semaphore_create(0);
  _manager.entitlementsBlocks = (NSMutableArray *)[[QNLockOrderArray alloc]
      initWithObjectAddedSemaphore:objectAdded];

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    [self.manager.identityMutationLock lock];
    dispatch_semaphore_signal(mutationLockHeld);
    dispatch_semaphore_wait(objectAdded, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC));
    @synchronized (self.manager) {
      [self.manager.identityMutationLock unlock];
    }
    dispatch_semaphore_signal(unlockFinished);
  });
  XCTAssertEqual(dispatch_semaphore_wait(mutationLockHeld, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    [self.manager checkEntitlements:^(NSDictionary<NSString *, QONEntitlement *> *result, NSError *error) {}];
    dispatch_semaphore_signal(checkFinished);
  });

  XCTAssertEqual(dispatch_semaphore_wait(unlockFinished, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0,
                 @"callback storage must release @synchronized(self) before waiting for identityMutationLock");
  XCTAssertEqual(dispatch_semaphore_wait(checkFinished, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
}

- (void)testExecuteUserBlocksDoesNotHoldManagerMonitorDuringExternalCallbacks {
  dispatch_semaphore_t callbackEntered = dispatch_semaphore_create(0);
  dispatch_semaphore_t allowMonitorAttempt = dispatch_semaphore_create(0);
  dispatch_semaphore_t monitorAcquired = dispatch_semaphore_create(0);
  dispatch_semaphore_t backgroundFinished = dispatch_semaphore_create(0);
  __block BOOL monitorWasAvailableDuringCallback = NO;

  self.manager.userInfoBlocks = [@[^(QONUser *user, NSError *error) {
    dispatch_semaphore_signal(callbackEntered);
    dispatch_semaphore_signal(allowMonitorAttempt);
    monitorWasAvailableDuringCallback = dispatch_semaphore_wait(
        monitorAcquired, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0;
  }] mutableCopy];

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    [self.manager.identityMutationLock lock];
    dispatch_semaphore_wait(callbackEntered, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC));
    dispatch_semaphore_wait(allowMonitorAttempt, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC));
    @synchronized (self.manager) {
      [self.manager.identityMutationLock unlock];
    }
    dispatch_semaphore_signal(monitorAcquired);
    dispatch_semaphore_signal(backgroundFinished);
  });

  [self.manager executeUserBlocks];

  XCTAssertTrue(monitorWasAvailableDuringCallback,
                @"external callbacks must run after releasing the manager monitor");
  XCTAssertEqual(dispatch_semaphore_wait(backgroundFinished, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
}

// MARK: - SUP3-30: actualizeEntitlements must preserve backend entitlements on error

- (void)testActualizeEntitlements_backendReturnsEntitlementsWithError_preservesEntitlements {
  // Given: Backend returns entitlements (Stripe) AND error (empty Apple receipt)
  // This simulates a Stripe user on iOS where backend returns valid entitlements
  // but StoreKit throws SKError.paymentInvalid due to missing Apple receipt.
  XCTestExpectation *expectation = [self expectationWithDescription:@"entitlements preserved"];

  NSError *skError = [NSError errorWithDomain:@"SKErrorDomain"
                                         code:4 // SKErrorPaymentInvalid
                                     userInfo:@{NSLocalizedDescriptionKey: @"Purchase identifier was invalid"}];

  OCMStub([_mockClient launchRequest:QONRequestTriggerActualizePermissions
                          completion:([OCMArg invokeBlockWithArgs:[self JSONObjectFromContentsOfFile:keyQNInitFullSuccessJSON], skError, nil])]);

  // When
  [_manager actualizeEntitlements:^(NSDictionary<NSString *, QONEntitlement *> * _Nonnull result, NSError * _Nullable error) {
    // Then: Backend entitlements should be returned, error should be nil
    XCTAssertNotNil(result, @"Backend entitlements should not be discarded");
    XCTAssertGreaterThan(result.count, 0, @"Should have at least one entitlement from backend");
    XCTAssertNil(error, @"Error should be nil when backend returned valid entitlements");

    [expectation fulfill];
  }];

  [self waitForExpectationsWithTimeout:keyQNTestTimeout handler:nil];
}

- (void)testActualizeEntitlements_backendReturnsNoEntitlementsWithError_returnsError {
  // Given: Backend returns empty entitlements AND error
  XCTestExpectation *expectation = [self expectationWithDescription:@"error returned"];

  NSError *skError = [NSError errorWithDomain:@"SKErrorDomain"
                                         code:4
                                     userInfo:nil];

  // init_failed_state.json has no permissions/entitlements
  OCMStub([_mockClient launchRequest:QONRequestTriggerActualizePermissions
                          completion:([OCMArg invokeBlockWithArgs:[self JSONObjectFromContentsOfFile:keyQNInitFailedJSON], skError, nil])]);

  // When
  [_manager actualizeEntitlements:^(NSDictionary<NSString *, QONEntitlement *> * _Nonnull result, NSError * _Nullable error) {
    // Then: Error should be returned since no entitlements available
    XCTAssertNotNil(error, @"Error should be returned when no entitlements available");
    XCTAssertEqual(error.code, 4, @"Error code should be preserved");

    [expectation fulfill];
  }];

  [self waitForExpectationsWithTimeout:keyQNTestTimeout handler:nil];
}

- (void)testActualizeEntitlements_backendReturnsEntitlementsNoError_returnsEntitlements {
  // Given: Normal case - backend returns entitlements without error
  XCTestExpectation *expectation = [self expectationWithDescription:@"normal case"];

  OCMStub([_mockClient launchRequest:QONRequestTriggerActualizePermissions
                          completion:([OCMArg invokeBlockWithArgs:[self JSONObjectFromContentsOfFile:keyQNInitFullSuccessJSON], [NSNull null], nil])]);

  // When
  [_manager actualizeEntitlements:^(NSDictionary<NSString *, QONEntitlement *> * _Nonnull result, NSError * _Nullable error) {
    // Then
    XCTAssertNotNil(result);
    XCTAssertEqual(result.count, 2);
    XCTAssertNil(error);

    [expectation fulfill];
  }];

  [self waitForExpectationsWithTimeout:keyQNTestTimeout handler:nil];
}

@end
