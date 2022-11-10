//
//  QNIdentityManagerTests.m
//  QonversionTests
//
//  Created by Surik Sarkisyan on 17.09.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>

#import "XCTestCase+Helpers.h"
#import "QNIdentityManager.h"
#import "QNIdentityServiceInterface.h"
#import "QNUserInfoServiceInterface.h"

@interface QNIdentityManagerTests : XCTestCase

@property (nonatomic, strong) id<QNIdentityServiceInterface> mockIdentityService;
@property (nonatomic, strong) id<QNUserInfoServiceInterface> mockUserInfoService;

@property (nonatomic, strong) QNIdentityManager *manager;

@end

@implementation QNIdentityManagerTests

- (void)setUp {
  [super setUp];
  
  self.manager = [QNIdentityManager new];
  
  self.mockIdentityService = OCMStrictProtocolMock(@protocol(QNIdentityServiceInterface));
  self.mockUserInfoService = OCMStrictProtocolMock(@protocol(QNUserInfoServiceInterface));
  
  self.manager.identityService = self.mockIdentityService;
  self.manager.userInfoService = self.mockUserInfoService;
}

- (void)tearDown {
  self.manager = nil;
  
  [super tearDown];
}

- (void)testSuccessIdentity {
  // given
  NSString *userID = @"random_user_id";
  NSString *anonUserID = @"anon_user_id";
  NSString *identityID = @"result_identity_id";
  NSError *randomError = [QONErrors deferredTransactionError]; // just a random error
  
  __block NSString *resultString;
  __block NSError *resultError;
  
  TestBlock testBlock = ^(NSInvocation *invocation) {
    void(^completioinBlock)(NSString *result, NSError *error);
    
    [invocation getArgument:&completioinBlock atIndex:4];
    
    completioinBlock(identityID, randomError);
  };
  
  OCMStub([self.mockUserInfoService obtainUserID]).andReturn(anonUserID);
  OCMStub([self.mockIdentityService identify:userID anonUserID:anonUserID completion:OCMOCK_ANY]).andDo(testBlock);
  
  OCMExpect([self.mockUserInfoService storeIdentity:identityID]);
  
  // when
  [self.manager identify:userID completion:^(NSString * _Nullable result, NSError * _Nullable error) {
    resultString = result;
    resultError = error;
  }];
  
  // then
  XCTAssertEqual(resultString, identityID);
  XCTAssertEqual(randomError, resultError);
  
  OCMVerify([self.mockUserInfoService obtainUserID]);
  OCMVerify([self.mockUserInfoService storeIdentity:identityID]);
  
  OCMVerify([self.mockIdentityService identify:userID anonUserID:anonUserID completion:OCMOCK_ANY]);
}

- (void)testSuccessIdentity_emptyID {
  // given
  NSString *userID = @"random_user_id";
  NSString *anonUserID = @"anon_user_id";
  NSString *identityID = @"";
  NSError *randomError = [QONErrors deferredTransactionError]; // just a random error
  
  __block NSString *resultString;
  __block NSError *resultError;
  
  TestBlock testBlock = ^(NSInvocation *invocation) {
    void(^completioinBlock)(NSString *result, NSError *error);
    
    [invocation getArgument:&completioinBlock atIndex:4];
    
    completioinBlock(identityID, randomError);
  };
  
  OCMStub([self.mockUserInfoService obtainUserID]).andReturn(anonUserID);
  OCMStub([self.mockIdentityService identify:userID anonUserID:anonUserID completion:OCMOCK_ANY]).andDo(testBlock);
  
  // when
  [self.manager identify:userID completion:^(NSString * _Nullable result, NSError * _Nullable error) {
    resultString = result;
    resultError = error;
  }];
  
  // then
  XCTAssertEqual(resultString, identityID);
  XCTAssertEqual(randomError, resultError);
  
  OCMVerify([self.mockUserInfoService obtainUserID]);
  
  OCMVerify([self.mockIdentityService identify:userID anonUserID:anonUserID completion:OCMOCK_ANY]);
}

- (void)testFailureIdentity {
  // given
  NSString *userID = @"random_user_id";
  NSString *anonUserID = @"anon_user_id";
  
  NSError *randomError = [QONErrors deferredTransactionError]; // just a random error
  
  __block NSString *resultString;
  __block NSError *resultError;
  
  TestBlock testBlock = ^(NSInvocation *invocation) {
    void(^completioinBlock)(NSString *result, NSError *error);
    
    [invocation getArgument:&completioinBlock atIndex:4];
    
    completioinBlock(nil, randomError);
  };
  
  OCMStub([self.mockUserInfoService obtainUserID]).andReturn(anonUserID);
  OCMStub([self.mockIdentityService identify:userID anonUserID:anonUserID completion:OCMOCK_ANY]).andDo(testBlock);
  
  // when
  [self.manager identify:userID completion:^(NSString * _Nullable result, NSError * _Nullable error) {
    resultString = result;
    resultError = error;
  }];
  
  // then
  XCTAssertEqual(resultError, randomError);
  XCTAssertNil(resultString);
  
  OCMVerify([self.mockUserInfoService obtainUserID]);
  
  OCMVerify([self.mockIdentityService identify:userID anonUserID:anonUserID completion:OCMOCK_ANY]);
}

- (void)testLogoutIfNeeded {
  // given
  OCMExpect([self.mockUserInfoService logoutIfNeeded]);
  
  // when
  [self.manager logoutIfNeeded];
  
  // then
  OCMVerifyAll(self.mockUserInfoService);
}

@end
