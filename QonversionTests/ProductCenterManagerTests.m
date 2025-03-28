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

- (void)checkEntitlements:(QONEntitlementsCompletionHandler)result;

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

@end
