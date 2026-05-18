//
//  QONTransactionCommitmentInfoTests.m
//  QonversionTests
//
//  Created by Qonversion on 2026.
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "QONTransactionCommitmentInfo.h"

@interface QONTransactionCommitmentInfoTests : XCTestCase
@end

@implementation QONTransactionCommitmentInfoTests

- (void)testQONTransactionCommitmentInfo_init_setsAllFields {
  NSDecimalNumber *price = [NSDecimalNumber decimalNumberWithString:@"9.99"];
  NSDate *expirationDate = [NSDate dateWithTimeIntervalSince1970:1800000000];

  QONTransactionCommitmentInfo *info = [[QONTransactionCommitmentInfo alloc]
    initWithBillingPeriodNumber:4
    totalBillingPeriods:12
    pricePerBillingPeriod:price
    currentBillingPeriodExpirationDate:expirationDate];

  XCTAssertEqual(info.billingPeriodNumber, (NSUInteger)4);
  XCTAssertEqual(info.totalBillingPeriods, (NSUInteger)12);
  XCTAssertEqualObjects(info.pricePerBillingPeriod, price);
  XCTAssertEqualObjects(info.currentBillingPeriodExpirationDate, expirationDate);
}

- (void)testQONTransactionCommitmentInfo_NSCoding_roundtrip {
  NSDecimalNumber *price = [NSDecimalNumber decimalNumberWithString:@"4.99"];
  NSDate *expirationDate = [NSDate dateWithTimeIntervalSince1970:2000000000];

  QONTransactionCommitmentInfo *original = [[QONTransactionCommitmentInfo alloc]
    initWithBillingPeriodNumber:2
    totalBillingPeriods:6
    pricePerBillingPeriod:price
    currentBillingPeriodExpirationDate:expirationDate];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  NSData *data = [NSKeyedArchiver archivedDataWithRootObject:original];
  QONTransactionCommitmentInfo *decoded = [NSKeyedUnarchiver unarchiveObjectWithData:data];
#pragma clang diagnostic pop

  XCTAssertNotNil(decoded);
  XCTAssertEqual(decoded.billingPeriodNumber, (NSUInteger)2);
  XCTAssertEqual(decoded.totalBillingPeriods, (NSUInteger)6);
  XCTAssertEqualObjects(decoded.pricePerBillingPeriod, price);
  XCTAssertEqualObjects(decoded.currentBillingPeriodExpirationDate, expirationDate);
}

@end
