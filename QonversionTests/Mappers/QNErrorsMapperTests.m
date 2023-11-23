//
//  QNErrorsMapperTests.m
//  QonversionTests
//
//  Created by Surik Sarkisyan on 29.09.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>
#import "QNErrorsMapper.h"
#import "QONErrors.h"
#import <Foundation/Foundation.h>

@interface QNErrorsMapper ()

- (NSString *)messageForErrorType:(QONAPIError)errorType;
- (QONAPIError)errorTypeFromCode:(NSNumber *)errorCode;

@end

@interface QNErrorsMapperTests : XCTestCase

@property (nonatomic, strong) QNErrorsMapper *mapper;
@property (nonatomic, copy) NSDictionary<NSNumber *, NSString *> *errorsMap;
@property (nonatomic, copy) NSDictionary<NSNumber *, NSNumber *> *errorsCodesMap;

@end

@implementation QNErrorsMapperTests

- (void)setUp {
  [super setUp];
  
  self.errorsMap = @{@(QONAPIErrorProjectConfigError) : @"The project is not configured or configured incorrectly in the Qonversion Dashboard.",
                     @(QONAPIErrorInvalidStoreCredentials) : @"Please check provided Store keys in the Qonversion Dashboard.",
                     @(QONAPIErrorReceiptValidation) : @"Provided receipt can't be validated. Please check the details here: https://documentation.qonversion.io/docs/troubleshooting#receipt-validation-error"
  };
  
  self.errorsCodesMap = @{
    @10000 : @3,
    @10001 : @3,
    @10007 : @3,
    @10009 : @3,
    @20000 : @3,
    @20009 : @3,
    @20015 : @3,
    @20099 : @3,
    @20300 : @3,
    @20303 : @3,
    @20200 : @3,
    @10002 : @5,
    @10003 : @5,
    @10004: @6,
    @10005: @6,
    @20014: @6,
    @10006: @7,
    @10008: @8,
    @20005: @9,
    @20006: @10,
    @20007: @10,
    @20109: @10,
    @20199: @10,
    @20008: @11,
    @20010: @11,
    @20011: @12,
    @20012: @12,
    @20013: @12,
    @20104: @13,
    @20102: @14,
    @20103: @14,
    @20105: @14,
    @20110: @14,
    @20100: @14,
    @20107: @14,
    @20108: @14,
    @21099: @14
  };
  
  self.mapper = [QNErrorsMapper new];
}

- (void)tearDown {
  self.mapper = nil;
  
  [super tearDown];
}

- (void)testErrorFromRequestResult_notDict {
  // given
  NSDictionary *someArray = (NSDictionary *)@[];
  
  // when
  NSError *error = [self.mapper errorFromRequestResult:someArray];
  
  // then
  XCTAssertNil(error);
}

- (void)testErrorFromRequestResult_dataIsNotDictAndNoErrorField {
  // given
  NSDictionary *result = @{@"data": @[]};
  
  // when
  NSError *error = [self.mapper errorFromRequestResult:result];
  
  // then
  XCTAssertNil(error);
}

- (void)testErrorFromRequestResult_dataAndErrorIsNotDict {
  // given
  NSDictionary *result = @{@"data": @[], @"error": @[]};
  
  // when
  NSError *error = [self.mapper errorFromRequestResult:result];
  
  // then
  XCTAssertNil(error);
}

- (void)testErrorFromRequestResult_success {
  // given
  NSDictionary *result = @{@"data": @{}, @"error": @{}, @"success": @(1)};
  
  // when
  NSError *error = [self.mapper errorFromRequestResult:result];
  
  // then
  XCTAssertNil(error);
}

- (void)testErrorFromRequestResult_fromDataFieldEmptyCode {
  // given
  NSDictionary *data = @{};
  NSDictionary *result = @{@"data": data, @"error": @{}, @"success": @(0)};
  
  // when
  NSError *error = [self.mapper errorFromRequestResult:result];
  
  // then
  XCTAssertEqual(error.code, 3);
  XCTAssertEqualObjects(error.localizedDescription, @"Internal error occurred");
}

- (void)testErrorFromRequestResult_fromDataField {
  // given
  NSUInteger resultAPIErrorType = 12;
  NSString *errorMessage = @"someMessage";
  NSNumber *code = @20012;
  NSString *failureReason = self.errorsMap[@(resultAPIErrorType)];
  NSString *tempAdditionalMessage = [NSString stringWithFormat:@"Internal error code: %li.", (long)code.integerValue];
  NSString *additionalMessage = [NSString stringWithFormat:@"%@\n%@", tempAdditionalMessage, failureReason];

  NSDictionary *data = @{@"message": errorMessage, @"code": code};
  NSDictionary *result = @{@"data": data, @"error": @{}, @"success": @(0)};
  
  // when
  NSError *error = [self.mapper errorFromRequestResult:result];
  
  // then
  XCTAssertEqual(error.code, resultAPIErrorType);
  XCTAssertEqualObjects(error.localizedDescription, errorMessage);
  XCTAssertEqualObjects(error.userInfo[NSDebugDescriptionErrorKey], additionalMessage);
}

- (void)testErrorFromRequestResult_fromDataFieldNoFailureReason {
  // given
  NSUInteger resultAPIErrorType = 11;
  NSString *errorMessage = @"someMessage";
  NSNumber *code = @20008;
  NSString *additionalMessage = [NSString stringWithFormat:@"Internal error code: %li.", (long)code.integerValue];

  NSDictionary *data = @{@"message": errorMessage, @"code": code};
  NSDictionary *result = @{@"data": data, @"error": @{}, @"success": @(0)};
  
  // when
  NSError *error = [self.mapper errorFromRequestResult:result];
  
  // then
  XCTAssertEqual(error.code, resultAPIErrorType);
  XCTAssertEqualObjects(error.localizedDescription, errorMessage);
  XCTAssertEqualObjects(error.userInfo[NSDebugDescriptionErrorKey], additionalMessage);
}

- (void)testErrorFromRequestResult_fromErrorField {
  // given
  NSString *errorMessage = @"someMessage";
  NSDictionary *errorDict = @{@"message": errorMessage};
  NSDictionary *result = @{@"error": errorDict, @"success": @(0)};
  
  // when
  NSError *error = [self.mapper errorFromRequestResult:result];
  
  // then
  XCTAssertEqual(error.code, 3);
  XCTAssertEqualObjects(error.localizedDescription, errorMessage);
}

- (void)testErrorFromRequestResult_fromErrorFieldNoMessage {
  // given
  NSDictionary *result = @{@"error": @{}, @"success": @(0)};
  
  // when
  NSError *error = [self.mapper errorFromRequestResult:result];
  
  // then
  XCTAssertEqual(error.code, 3);
  XCTAssertEqualObjects(error.localizedDescription, @"Internal error occurred");
}

- (void)testMessageForErrorType {
  // given
  NSDictionary<NSNumber *, NSString *> *testErrorsMap = self.errorsMap;
  
  for (NSNumber *key in testErrorsMap) {
    // when
    NSString *message = [self.mapper messageForErrorType:key.integerValue];
    
    // then
    XCTAssertEqualObjects(message, testErrorsMap[key]);
  }
}

- (void)testMessageForErrorType_unknownValue {
  // given
  NSInteger randomValue = 12; // first value from self.errorsMap
  while (self.errorsMap[@(randomValue)]) {
    randomValue = rand();
  }

  // when
  NSString *message = [self.mapper messageForErrorType:randomValue];
  
  // then
  XCTAssertNil(message);
}

- (void)testErrorTypeFromCode {
  // given
  NSDictionary<NSNumber *, NSNumber *> *errorsCodesMap = self.errorsCodesMap;
  
  for (NSNumber *key in errorsCodesMap) {
    // when
    NSUInteger type = [self.mapper errorTypeFromCode:key];
    
    // then
    XCTAssertEqual(type, errorsCodesMap[key].integerValue);
  }
}

- (void)testErrorTypeFromCode_unknownValue {
  // given
  NSInteger randomValue = 10000; // first value from self.errorsCodesMap
  while (self.errorsCodesMap[@(randomValue)]) {
    randomValue = rand();
  }
  
  // when
  NSUInteger type = [self.mapper errorTypeFromCode:@(randomValue)];
  
  // then
  XCTAssertEqual(type, 3);
}

@end
