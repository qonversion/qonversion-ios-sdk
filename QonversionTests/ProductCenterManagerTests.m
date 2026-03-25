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
@property (nonatomic) QNAPIClient *apiClient;

@property (nonatomic) QONLaunchResult *launchResult;
@property (nonatomic) NSError *launchError;

@property (nonatomic, assign) BOOL launchingFinished;
@property (nonatomic, assign) BOOL productsLoaded;

@property (nonatomic, copy) NSString *pendingIdentityUserID;

- (void)checkEntitlements:(QONEntitlementsCompletionHandler)result;
- (void)actualizeEntitlements:(QONEntitlementsCompletionHandler)completion;

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
