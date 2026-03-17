#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>
#import "QNProductCenterManager.h"
#import "QNAPIClient.h"
#import "QNUserInfoService.h"
#import "QNIdentityManager.h"
#import "QNLocalStorage.h"
#import "QONFallbackService.h"
#import "QONDeferredPurchaseListener.h"
#import "QONEntitlementsUpdateListener.h"
#import "QONEntitlement.h"
#import "QONPurchaseResult.h"
#import "QONPurchaseResult+Protected.h"
#import "QNTestConstants.h"

@interface QNProductCenterManager (DeferredTestPrivate)

@property (nonatomic, weak) id<QONEntitlementsUpdateListener> purchasesDelegate;
@property (nonatomic, weak) id<QONDeferredPurchaseListener> deferredPurchaseListener;

@end

@interface DeferredPurchaseListenerTests : XCTestCase

@property (nonatomic) QNProductCenterManager *manager;
@property (nonatomic) id mockDeferredListener;
@property (nonatomic) id mockEntitlementsListener;

@end

@implementation DeferredPurchaseListenerTests

- (void)setUp {
  id mockUserInfoService = OCMClassMock([QNUserInfoService class]);
  id mockIdentityManager = OCMClassMock([QNIdentityManager class]);
  id mockLocalStorage = OCMProtocolMock(@protocol(QNLocalStorage));
  id mockFallbackService = OCMClassMock([QONFallbackService class]);
  _manager = [[QNProductCenterManager alloc] initWithUserInfoService:mockUserInfoService identityManager:mockIdentityManager localStorage:mockLocalStorage fallbackService:mockFallbackService];

  _mockDeferredListener = OCMProtocolMock(@protocol(QONDeferredPurchaseListener));
  _mockEntitlementsListener = OCMProtocolMock(@protocol(QONEntitlementsUpdateListener));
}

- (void)tearDown {
  _manager = nil;
  _mockDeferredListener = nil;
  _mockEntitlementsListener = nil;
}

#pragma mark - Setter Tests

- (void)testSetDeferredPurchaseListenerStoresListener {
  // When
  [_manager setDeferredPurchaseListener:_mockDeferredListener];

  // Then
  XCTAssertEqual(_manager.deferredPurchaseListener, _mockDeferredListener);
}

- (void)testSetDeferredPurchaseListenerToNilClearsListener {
  // Given
  [_manager setDeferredPurchaseListener:_mockDeferredListener];

  // When
  [_manager setDeferredPurchaseListener:nil];

  // Then
  XCTAssertNil(_manager.deferredPurchaseListener);
}

- (void)testSetDeferredPurchaseListenerReplacesExisting {
  // Given
  id anotherListener = OCMProtocolMock(@protocol(QONDeferredPurchaseListener));
  [_manager setDeferredPurchaseListener:_mockDeferredListener];

  // When
  [_manager setDeferredPurchaseListener:anotherListener];

  // Then
  XCTAssertEqual(_manager.deferredPurchaseListener, anotherListener);
}

#pragma mark - Coexistence Tests

- (void)testBothListenersCanBeSetIndependently {
  // When
  [_manager setPurchasesDelegate:_mockEntitlementsListener];
  [_manager setDeferredPurchaseListener:_mockDeferredListener];

  // Then
  XCTAssertEqual(_manager.purchasesDelegate, _mockEntitlementsListener);
  XCTAssertEqual(_manager.deferredPurchaseListener, _mockDeferredListener);
}

- (void)testSettingDeferredListenerDoesNotAffectEntitlementsListener {
  // Given
  [_manager setPurchasesDelegate:_mockEntitlementsListener];

  // When
  [_manager setDeferredPurchaseListener:_mockDeferredListener];

  // Then
  XCTAssertEqual(_manager.purchasesDelegate, _mockEntitlementsListener);
}

- (void)testSettingEntitlementsListenerDoesNotAffectDeferredListener {
  // Given
  [_manager setDeferredPurchaseListener:_mockDeferredListener];

  // When
  [_manager setPurchasesDelegate:_mockEntitlementsListener];

  // Then
  XCTAssertEqual(_manager.deferredPurchaseListener, _mockDeferredListener);
}

@end
