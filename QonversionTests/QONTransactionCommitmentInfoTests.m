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
    commitmentPrice:price
    commitmentExpirationDate:expirationDate];

  XCTAssertEqual(info.billingPeriodNumber, (NSUInteger)4);
  XCTAssertEqual(info.totalBillingPeriods, (NSUInteger)12);
  XCTAssertEqualObjects(info.commitmentPrice, price);
  XCTAssertEqualObjects(info.commitmentExpirationDate, expirationDate);
}

- (void)testQONTransactionCommitmentInfo_NSCoding_roundtrip {
  NSDecimalNumber *price = [NSDecimalNumber decimalNumberWithString:@"4.99"];
  NSDate *expirationDate = [NSDate dateWithTimeIntervalSince1970:2000000000];

  QONTransactionCommitmentInfo *original = [[QONTransactionCommitmentInfo alloc]
    initWithBillingPeriodNumber:2
    totalBillingPeriods:6
    commitmentPrice:price
    commitmentExpirationDate:expirationDate];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  NSData *data = [NSKeyedArchiver archivedDataWithRootObject:original];
  QONTransactionCommitmentInfo *decoded = [NSKeyedUnarchiver unarchiveObjectWithData:data];
#pragma clang diagnostic pop

  XCTAssertNotNil(decoded);
  XCTAssertEqual(decoded.billingPeriodNumber, (NSUInteger)2);
  XCTAssertEqual(decoded.totalBillingPeriods, (NSUInteger)6);
  XCTAssertEqualObjects(decoded.commitmentPrice, price);
  XCTAssertEqualObjects(decoded.commitmentExpirationDate, expirationDate);
}

@end
