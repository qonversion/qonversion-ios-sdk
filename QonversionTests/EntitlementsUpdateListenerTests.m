#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>
#import "QNProductCenterManager.h"
#import "QNAPIClient.h"
#import "QNStoreKitService.h"
#import "QNTestConstants.h"
#import "QONLaunchResult.h"
#import "QNUserInfoService.h"
#import "QNIdentityManager.h"
#import "QNLocalStorage.h"
#import "QONFallbackService.h"
#import "QONEntitlementsUpdateListener.h"
#import "QONPurchaseResult.h"
#import "QONEntitlement.h"

@interface QNProductCenterManager (ListenerTestPrivate)

@property (nonatomic, weak) id<QONEntitlementsUpdateListener> purchasesDelegate;

@end

// MARK: - Mock listener implementing ONLY the old method (backward compat)
@interface MockOldEntitlementsListener : NSObject <QONEntitlementsUpdateListener>

@property (nonatomic, strong) NSDictionary<NSString *, QONEntitlement *> *receivedEntitlements;
@property (nonatomic, assign) BOOL didReceiveCalled;

@end

@implementation MockOldEntitlementsListener

- (void)didReceiveUpdatedEntitlements:(NSDictionary<NSString *, QONEntitlement *> *)entitlements {
  self.receivedEntitlements = entitlements;
  self.didReceiveCalled = YES;
}

@end

// MARK: - Mock listener implementing the NEW method with purchaseResult
@interface MockNewEntitlementsListener : NSObject <QONEntitlementsUpdateListener>

@property (nonatomic, strong) NSDictionary<NSString *, QONEntitlement *> *receivedEntitlements;
@property (nonatomic, strong) QONPurchaseResult *receivedPurchaseResult;
@property (nonatomic, assign) BOOL oldMethodCalled;
@property (nonatomic, assign) BOOL newMethodCalled;

@end

@implementation MockNewEntitlementsListener

- (void)didReceiveUpdatedEntitlements:(NSDictionary<NSString *, QONEntitlement *> *)entitlements {
  self.oldMethodCalled = YES;
}

- (void)didReceiveUpdatedEntitlements:(NSDictionary<NSString *, QONEntitlement *> *)entitlements
                       purchaseResult:(QONPurchaseResult *)purchaseResult {
  self.receivedEntitlements = entitlements;
  self.receivedPurchaseResult = purchaseResult;
  self.newMethodCalled = YES;
}

@end

// MARK: - Tests

@interface EntitlementsUpdateListenerTests : XCTestCase

@property (nonatomic, strong) QNProductCenterManager *manager;

@end

@implementation EntitlementsUpdateListenerTests

- (void)setUp {
  id mockUserInfoService = OCMClassMock([QNUserInfoService class]);
  id mockIdentityManager = OCMClassMock([QNIdentityManager class]);
  id mockLocalStorage = OCMProtocolMock(@protocol(QNLocalStorage));
  id mockFallbackService = OCMClassMock([QONFallbackService class]);
  _manager = [[QNProductCenterManager alloc] initWithUserInfoService:mockUserInfoService
                                                     identityManager:mockIdentityManager
                                                        localStorage:mockLocalStorage
                                                     fallbackService:mockFallbackService];
}

- (void)tearDown {
  _manager = nil;
}

#pragma mark - Protocol Conformance Tests

- (void)testOldListenerConformsToProtocol {
  MockOldEntitlementsListener *listener = [MockOldEntitlementsListener new];
  XCTAssertTrue([listener conformsToProtocol:@protocol(QONEntitlementsUpdateListener)]);
}

- (void)testNewListenerConformsToProtocol {
  MockNewEntitlementsListener *listener = [MockNewEntitlementsListener new];
  XCTAssertTrue([listener conformsToProtocol:@protocol(QONEntitlementsUpdateListener)]);
}

#pragma mark - Old Listener (backward compatibility)

- (void)testOldListenerReceivesEntitlements {
  MockOldEntitlementsListener *listener = [MockOldEntitlementsListener new];
  NSDictionary *entitlements = @{};

  [listener didReceiveUpdatedEntitlements:entitlements];

  XCTAssertTrue(listener.didReceiveCalled);
  XCTAssertEqualObjects(listener.receivedEntitlements, entitlements);
}

- (void)testOldListenerDoesNotRespondToNewSelector {
  MockOldEntitlementsListener *listener = [MockOldEntitlementsListener new];

  BOOL respondsToNew = [listener respondsToSelector:@selector(didReceiveUpdatedEntitlements:purchaseResult:)];
  XCTAssertFalse(respondsToNew);
}

#pragma mark - New Listener

- (void)testNewListenerRespondsToNewSelector {
  MockNewEntitlementsListener *listener = [MockNewEntitlementsListener new];

  BOOL respondsToNew = [listener respondsToSelector:@selector(didReceiveUpdatedEntitlements:purchaseResult:)];
  XCTAssertTrue(respondsToNew);
}

- (void)testNewListenerReceivesEntitlementsAndPurchaseResult {
  MockNewEntitlementsListener *listener = [MockNewEntitlementsListener new];
  NSDictionary *entitlements = @{};

  [listener didReceiveUpdatedEntitlements:entitlements purchaseResult:nil];

  XCTAssertTrue(listener.newMethodCalled);
  XCTAssertFalse(listener.oldMethodCalled);
  XCTAssertEqualObjects(listener.receivedEntitlements, entitlements);
  XCTAssertNil(listener.receivedPurchaseResult);
}

#pragma mark - Delegate Assignment

- (void)testSetEntitlementsUpdateListenerAssignsDelegate {
  MockOldEntitlementsListener *listener = [MockOldEntitlementsListener new];
  [_manager setEntitlementsUpdateListener:listener];

  XCTAssertEqualObjects(_manager.purchasesDelegate, listener);
}

@end
