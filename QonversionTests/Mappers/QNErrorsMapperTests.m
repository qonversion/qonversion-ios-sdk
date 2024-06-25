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

- (NSString *)messageForErrorType:(QONErrorCode)errorType;
- (QONErrorCode)errorTypeFromCode:(NSNumber *)errorCode;

@end

@interface QNErrorsMapperTests : XCTestCase

@property (nonatomic, strong) QNErrorsMapper *mapper;
@property (nonatomic, copy) NSDictionary<NSNumber *, NSString *> *errorsMap;
@property (nonatomic, copy) NSDictionary<NSNumber *, NSNumber *> *errorsCodesMap;

@end

@implementation QNErrorsMapperTests

- (void)setUp {
  [super setUp];
  
  self.errorsMap = @{@(QONErrorCodeProjectConfigError) : @"The project is not configured or configured incorrectly in the Qonversion Dashboard.",
                     @(QONErrorCodeInvalidStoreCredentials) : @"Please check provided Store keys in the Qonversion Dashboard.",
                     @(QONErrorCodeReceiptValidationError) : @"Provided receipt can't be validated. Please check the details here: https://documentation.qonversion.io/docs/troubleshooting#receipt-validation-error"
  };
  
  self.errorsCodesMap = @{
    @10000 : @23,
    @10001 : @23,
    @10007 : @23,
    @10009 : @23,
    @20000 : @23,
    @20009 : @23,
    @20015 : @23,
    @20099 : @23,
    @20300 : @23,
    @20303 : @23,
    @20200 : @23,
    @10002 : @25,
    @10003 : @25,
    @10004: @26,
    @10005: @26,
    @20014: @26,
    @10006: @27,
    @10008: @28,
    @20005: @29,
    @20006: @30,
    @20007: @30,
    @20109: @30,
    @20199: @30,
    @20008: @31,
    @20010: @31,
    @20011: @32,
    @20012: @32,
    @20013: @32,
    @20104: @33,
    @20102: @34,
    @20103: @34,
    @20105: @34,
    @20110: @34,
    @20100: @34,
    @20107: @34,
    @20108: @34,
    @21099: @34
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
  XCTAssertEqual(error.code, 23);
  XCTAssertEqualObjects(error.localizedDescription, @"Internal error occurred");
}

- (void)testErrorFromRequestResult_fromDataField {
  // given
  NSUInteger resultAPIErrorType = 32;
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
  NSUInteger resultAPIErrorType = 31;
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
  XCTAssertEqual(error.code, 23);
  XCTAssertEqualObjects(error.localizedDescription, errorMessage);
}

- (void)testErrorFromRequestResult_fromErrorFieldNoMessage {
  // given
  NSDictionary *result = @{@"error": @{}, @"success": @(0)};
  
  // when
  NSError *error = [self.mapper errorFromRequestResult:result];
  
  // then
  XCTAssertEqual(error.code, 23);
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
  XCTAssertEqual(type, 23);
}

@end
