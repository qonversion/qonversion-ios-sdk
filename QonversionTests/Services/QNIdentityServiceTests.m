//
//  QNIdentityServiceTests.m
//  QonversionTests
//
//  Created by Surik Sarkisyan on 16.09.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>
#import "XCTestCase+Unmock.h"
#import "XCTestCase+Helpers.h"

#import "QNIdentityService.h"
#import "QNAPIClient.h"

@interface QNIdentityServiceTests : XCTestCase

@property (nonatomic, strong) QNIdentityService *service;
@property (nonatomic, strong) QNAPIClient *mockApiClient;

@end

@implementation QNIdentityServiceTests

- (void)setUp {
  [super setUp];
  
  self.mockApiClient = OCMClassMock([QNAPIClient class]);
  
  self.service = [QNIdentityService new];
  
  self.service.apiClient = self.mockApiClient;
}

- (void)tearDown {
  [self unmock:self.mockApiClient];
  
  self.service = nil;
  
  [super tearDown];
}

- (void)testSuccessIdentity {
  // given
  NSString *userID = @"random_user_id";
  NSString *anonUserID = @"anon_user_id";
  NSString *identityID = @"identity_id";
  
  __block NSString *resultString;
  __block NSError *resultError;
  
  NSDictionary *data = @{@"data": @{@"anon_id": identityID}};
  
  TestBlock testBlock = ^(NSInvocation *invocation) {
    void(^completioinBlock)(NSDictionary *data, NSError *error);
    
    [invocation getArgument:&completioinBlock atIndex:4];
    
    completioinBlock(data, nil);
  };
  
  OCMStub([self.mockApiClient createIdentityForUserID:userID anonUserID:anonUserID completion:OCMOCK_ANY]).andDo(testBlock);
  
  // when
  [self.service identify:userID anonUserID:anonUserID completion:^(NSString * _Nullable result, NSError * _Nullable error) {
    resultString = result;
    resultError = error;
  }];
  
  // then
  XCTAssertEqual(resultString, identityID);
  XCTAssertNil(resultError);
  
  OCMVerify([self.mockApiClient createIdentityForUserID:userID anonUserID:anonUserID completion:OCMOCK_ANY]);
}

- (void)testFailureIdentity {
  // given
  NSString *userID = @"random_user_id";
  NSString *anonUserID = @"anon_user_id";
  NSString *identityID = @"identity_id";
  NSError *randomError = [QONErrors deferredTransactionError]; // just a random error
  
  __block NSString *resultString;
  __block NSError *resultError;
  
  NSDictionary *data = @{@"data": @{@"anon_id_wrong_key": identityID}};
  
  TestBlock testBlock = ^(NSInvocation *invocation) {
    void(^completioinBlock)(NSDictionary *data, NSError *error);
    
    [invocation getArgument:&completioinBlock atIndex:4];
    
    completioinBlock(data, randomError);
  };
  
  OCMStub([self.mockApiClient createIdentityForUserID:userID anonUserID:anonUserID completion:OCMOCK_ANY]).andDo(testBlock);
  
  // when
  [self.service identify:userID anonUserID:anonUserID completion:^(NSString * _Nullable result, NSError * _Nullable error) {
    resultString = result;
    resultError = error;
  }];
  
  // then
  XCTAssertEqual(resultError, randomError);
  XCTAssertNil(resultString);
  
  OCMVerify([self.mockApiClient createIdentityForUserID:userID anonUserID:anonUserID completion:OCMOCK_ANY]);
}

- (void)testFailureIdentity_emptyID {
  // given
  NSString *userID = @"random_user_id";
  NSString *anonUserID = @"anon_user_id";
  NSString *identityID = @"";
  NSError *expectedError = [QONErrors errorWithQONErrorCode:QONErrorInternalError]; // just a random error
  
  __block NSString *resultString;
  __block NSError *resultError;
  
  NSDictionary *data = @{@"data": @{@"anon_id": identityID}};
  
  TestBlock testBlock = ^(NSInvocation *invocation) {
    void(^completioinBlock)(NSDictionary *data, NSError *error);
    
    [invocation getArgument:&completioinBlock atIndex:4];
    
    completioinBlock(data, nil);
  };
  
  OCMStub([self.mockApiClient createIdentityForUserID:userID anonUserID:anonUserID completion:OCMOCK_ANY]).andDo(testBlock);
  
  // when
  [self.service identify:userID anonUserID:anonUserID completion:^(NSString * _Nullable result, NSError * _Nullable error) {
    resultString = result;
    resultError = error;
  }];
  
  // then
  XCTAssertEqualObjects(resultError, expectedError);
  XCTAssertNil(resultString);
  
  OCMVerify([self.mockApiClient createIdentityForUserID:userID anonUserID:anonUserID completion:OCMOCK_ANY]);
}

@end
