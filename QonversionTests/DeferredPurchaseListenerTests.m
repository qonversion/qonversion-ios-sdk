#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>
#import "QNProductCenterManager.h"
#import "QNAPIClient.h"
#import "QNUserInfoService.h"
#import "QNIdentityManager.h"
#import "QNLocalStorage.h"
#import "QONFallbackService.h"
#import "QONDeferredPurchasesListener.h"
#import "QONEntitlementsUpdateListener.h"
#import "QONEntitlementsUpdateListenerAdapter.h"
#import "QONEntitlement.h"
#import "QONPurchaseResult.h"
#import "QONPurchaseResult+Protected.h"
#import "QNTestConstants.h"

@interface QNProductCenterManager (DeferredTestPrivate)

@property (nonatomic, strong) id<QONDeferredPurchasesListener> deferredPurchasesListener;
@property (nonatomic, strong) QONEntitlementsUpdateListenerAdapter *listenerAdapter;

@end

@interface DeferredPurchaseListenerTests : XCTestCase

@property (nonatomic) QNProductCenterManager *manager;

@end

@implementation DeferredPurchaseListenerTests

- (void)setUp {
  id mockUserInfoService = OCMClassMock([QNUserInfoService class]);
  id mockIdentityManager = OCMClassMock([QNIdentityManager class]);
  id mockLocalStorage = OCMProtocolMock(@protocol(QNLocalStorage));
  id mockFallbackService = OCMClassMock([QONFallbackService class]);
  _manager = [[QNProductCenterManager alloc] initWithUserInfoService:mockUserInfoService identityManager:mockIdentityManager localStorage:mockLocalStorage fallbackService:mockFallbackService];
}

- (void)tearDown {
  _manager = nil;
}

#pragma mark - Setter Tests

- (void)testSetDeferredPurchaseListenerStoresListener {
  id mockListener = OCMProtocolMock(@protocol(QONDeferredPurchasesListener));

  [_manager setDeferredPurchasesListener:mockListener];

  XCTAssertEqual(_manager.deferredPurchasesListener, mockListener);
}

- (void)testSetDeferredPurchaseListenerToNilClearsListener {
  id mockListener = OCMProtocolMock(@protocol(QONDeferredPurchasesListener));
  [_manager setDeferredPurchasesListener:mockListener];

  [_manager setDeferredPurchasesListener:nil];

  XCTAssertNil(_manager.deferredPurchasesListener);
}

- (void)testSetDeferredPurchaseListenerReplacesExisting {
  id firstListener = OCMProtocolMock(@protocol(QONDeferredPurchasesListener));
  id secondListener = OCMProtocolMock(@protocol(QONDeferredPurchasesListener));
  [_manager setDeferredPurchasesListener:firstListener];

  [_manager setDeferredPurchasesListener:secondListener];

  XCTAssertEqual(_manager.deferredPurchasesListener, secondListener);
}

#pragma mark - Adapter Pattern Tests

- (void)testSetPurchasesDelegateWrapsInAdapter {
  // When legacy setPurchasesDelegate is called, it should create an adapter
  // and set it as the deferredPurchasesListener.
  id mockLegacyListener = OCMProtocolMock(@protocol(QONEntitlementsUpdateListener));

  [_manager setPurchasesDelegate:mockLegacyListener];

  XCTAssertNotNil(_manager.deferredPurchasesListener);
  XCTAssertNotNil(_manager.listenerAdapter);
  XCTAssertTrue([_manager.deferredPurchasesListener conformsToProtocol:@protocol(QONDeferredPurchasesListener)]);
}

- (void)testSetPurchasesDelegateToNilClearsBoth {
  id mockLegacyListener = OCMProtocolMock(@protocol(QONEntitlementsUpdateListener));
  [_manager setPurchasesDelegate:mockLegacyListener];

  [_manager setPurchasesDelegate:nil];

  XCTAssertNil(_manager.deferredPurchasesListener);
  XCTAssertNil(_manager.listenerAdapter);
}

- (void)testSetDeferredListenerClearsAdapter {
  // Setting the new listener directly should clear any adapter from legacy listener.
  id mockLegacyListener = OCMProtocolMock(@protocol(QONEntitlementsUpdateListener));
  [_manager setPurchasesDelegate:mockLegacyListener];
  XCTAssertNotNil(_manager.listenerAdapter);

  id mockDeferredListener = OCMProtocolMock(@protocol(QONDeferredPurchasesListener));
  [_manager setDeferredPurchasesListener:mockDeferredListener];

  XCTAssertNil(_manager.listenerAdapter);
  XCTAssertEqual(_manager.deferredPurchasesListener, mockDeferredListener);
}

#pragma mark - Adapter Forwarding Tests

- (void)testAdapterForwardsEntitlementsFromPurchaseResult {
  // The adapter should extract entitlements from QONPurchaseResult
  // and forward them to the wrapped legacy listener.
  id mockLegacyListener = OCMProtocolMock(@protocol(QONEntitlementsUpdateListener));
  QONEntitlementsUpdateListenerAdapter *adapter = [[QONEntitlementsUpdateListenerAdapter alloc] initWithLegacyListener:mockLegacyListener];

  NSDictionary *entitlements = @{@"premium": OCMClassMock([QONEntitlement class])};
  QONPurchaseResult *purchaseResult = [QONPurchaseResult successWithEntitlements:entitlements transaction:nil];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  OCMExpect([mockLegacyListener didReceiveUpdatedEntitlements:entitlements]);
#pragma clang diagnostic pop

  [adapter deferredPurchaseCompleted:purchaseResult];

  OCMVerifyAll(mockLegacyListener);
}

@end
