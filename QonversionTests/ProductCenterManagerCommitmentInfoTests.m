//
//  ProductCenterManagerCommitmentInfoTests.m
//  QonversionTests
//
//  Created by Qonversion on 2026.
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
#import "QONEntitlement.h"
#import "QONTransaction.h"
#import "QONTransaction+Protected.h"
#import "QONTransactionCommitmentInfo.h"
#import "QONStoreKit2PurchaseModel.h"

@interface QNProductCenterManager (CommitmentInfoTests)
@property (nonatomic, strong) NSMutableDictionary<NSString *, QONTransactionCommitmentInfo *> *commitmentInfoByTransactionId;
- (void)cacheCommitmentInfoFromPurchaseModels:(NSArray<QONStoreKit2PurchaseModel *> *)purchaseModels;
- (void)enrichEntitlementsWithCommitmentInfo:(NSDictionary<NSString *, QONEntitlement *> *)entitlements;
@end

@interface ProductCenterManagerCommitmentInfoTests : XCTestCase
@property (nonatomic) QNProductCenterManager *manager;
@end

@implementation ProductCenterManagerCommitmentInfoTests

- (void)setUp {
  [super setUp];
  id userInfoService = OCMClassMock([QNUserInfoService class]);
  id identityManager = OCMClassMock([QNIdentityManager class]);
  id localStorage = OCMProtocolMock(@protocol(QNLocalStorage));
  id fallbackService = OCMClassMock([QONFallbackService class]);
  _manager = [[QNProductCenterManager alloc] initWithUserInfoService:userInfoService
                                                     identityManager:identityManager
                                                        localStorage:localStorage
                                                     fallbackService:fallbackService];
}

- (void)tearDown {
  _manager = nil;
  [super tearDown];
}

#pragma mark - Helpers

- (QONTransaction *)makeTransactionWithId:(NSString *)transactionId {
  return [[QONTransaction alloc] initWithOriginalTransactionId:transactionId
                                                 transactionId:transactionId
                                                     offerCode:nil
                                               transactionDate:[NSDate date]
                                                expirationDate:nil
                                     transactionRevocationDate:nil
                                                  promoOfferId:nil
                                                   environment:QONTransactionEnvironmentProduction
                                                 ownershipType:QONTransactionOwnershipTypeOwner
                                                          type:QONTransactionTypeSubscriptionRenewed];
}

- (QONEntitlement *)makeEntitlementWithTransactions:(NSArray<QONTransaction *> *)transactions {
  QONEntitlement *entitlement = [[QONEntitlement alloc] init];
  entitlement.entitlementID = @"premium";
  entitlement.productID = @"monthly_with_commitment";
  entitlement.transactions = transactions;
  return entitlement;
}

#pragma mark - Tests

- (void)testCacheAndEnrichmentAppliesCommitmentInfoOnce {
  if (@available(iOS 26.4, macOS 26.4, watchOS 26.4, tvOS 26.4, visionOS 26.4, *)) {
    // Given a purchase model carrying commitment info for transaction "txn-1"
    QONTransactionCommitmentInfo *info =
      [[QONTransactionCommitmentInfo alloc] initWithBillingPeriodNumber:4
                                                    totalBillingPeriods:12
                                                  pricePerBillingPeriod:[NSDecimalNumber decimalNumberWithString:@"9.99"]
                                     currentBillingPeriodExpirationDate:[NSDate dateWithTimeIntervalSince1970:1800000000]];

    QONStoreKit2PurchaseModel *model = [QONStoreKit2PurchaseModel new];
    model.transactionId = @"txn-1";
    model.commitmentInfo = info;

    // And an entitlement that holds a server-built QONTransaction with the same id
    QONTransaction *txn = [self makeTransactionWithId:@"txn-1"];
    QONEntitlement *entitlement = [self makeEntitlementWithTransactions:@[txn]];
    NSDictionary<NSString *, QONEntitlement *> *entitlements = @{@"premium": entitlement};

    // When the manager caches the SK2-side commitment info and then enriches entitlements
    [_manager cacheCommitmentInfoFromPurchaseModels:@[model]];
    XCTAssertEqualObjects(_manager.commitmentInfoByTransactionId[@"txn-1"], info);

    [_manager enrichEntitlementsWithCommitmentInfo:entitlements];

    // Then the transaction is enriched and the cache entry is consumed (one-shot)
    XCTAssertEqualObjects(txn.commitmentInfo, info);
    XCTAssertNil(_manager.commitmentInfoByTransactionId[@"txn-1"]);
    XCTAssertEqual(_manager.commitmentInfoByTransactionId.count, (NSUInteger)0);

    // And a second enrichment pass is a no-op (idempotent / no double-apply)
    txn.commitmentInfo = nil;
    [_manager enrichEntitlementsWithCommitmentInfo:entitlements];
    XCTAssertNil(txn.commitmentInfo);
  } else {
    XCTSkip(@"Requires iOS 26.4+");
  }
}

- (void)testEnrichmentLeavesCacheEntryWhenTransactionNotInEntitlements {
  if (@available(iOS 26.4, macOS 26.4, watchOS 26.4, tvOS 26.4, visionOS 26.4, *)) {
    // Given a cached commitment info for "txn-pending" that the backend has not yet
    // surfaced through entitlements (typical post-purchase / pre-launch window)
    QONTransactionCommitmentInfo *info =
      [[QONTransactionCommitmentInfo alloc] initWithBillingPeriodNumber:1
                                                    totalBillingPeriods:12
                                                  pricePerBillingPeriod:[NSDecimalNumber decimalNumberWithString:@"4.99"]
                                     currentBillingPeriodExpirationDate:[NSDate dateWithTimeIntervalSince1970:1900000000]];

    QONStoreKit2PurchaseModel *model = [QONStoreKit2PurchaseModel new];
    model.transactionId = @"txn-pending";
    model.commitmentInfo = info;
    [_manager cacheCommitmentInfoFromPurchaseModels:@[model]];

    // And an entitlements snapshot that only contains "txn-other"
    QONTransaction *otherTxn = [self makeTransactionWithId:@"txn-other"];
    QONEntitlement *entitlement = [self makeEntitlementWithTransactions:@[otherTxn]];

    // When we enrich
    [_manager enrichEntitlementsWithCommitmentInfo:@{@"premium": entitlement}];

    // Then "txn-other" is untouched and the cached info is preserved for the next pass
    XCTAssertNil(otherTxn.commitmentInfo);
    XCTAssertEqualObjects(_manager.commitmentInfoByTransactionId[@"txn-pending"], info);
  } else {
    XCTSkip(@"Requires iOS 26.4+");
  }
}

- (void)testCacheIgnoresPurchaseModelsWithoutCommitmentInfo {
  if (@available(iOS 26.4, macOS 26.4, watchOS 26.4, tvOS 26.4, visionOS 26.4, *)) {
    QONStoreKit2PurchaseModel *bare = [QONStoreKit2PurchaseModel new];
    bare.transactionId = @"txn-bare";
    // bare.commitmentInfo intentionally nil

    [_manager cacheCommitmentInfoFromPurchaseModels:@[bare]];

    XCTAssertEqual(_manager.commitmentInfoByTransactionId.count, (NSUInteger)0);
  } else {
    XCTSkip(@"Requires iOS 26.4+");
  }
}

@end
