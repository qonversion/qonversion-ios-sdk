//
//  QNUserInfoServiceTests.m
//  QonversionTests
//
//  Created by Surik Sarkisyan on 19.03.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>

#import "XCTestCase+Unmock.h"

#import "QNUserInfoService.h"
#import "QNLocalStorage.h"

@interface QNUserInfoServiceTests : XCTestCase

@property (nonatomic, strong) QNUserInfoService *service;
@property (nonatomic, strong) id<QNLocalStorage> mockLocalStorage;

@end

@implementation QNUserInfoServiceTests

- (void)setUp {
  [super setUp];
  
  self.service = [QNUserInfoService new];
  self.mockLocalStorage = OCMStrictProtocolMock(@protocol(QNLocalStorage));
  
  self.service.localStorage = self.mockLocalStorage;
}

- (void)tearDown {
  self.service = nil;
  
  [self unmock:self.mockLocalStorage];
    
  [super tearDown];
}

- (void)testObtainUserID_userDefaultsNotEmpty {
  // given
  NSString *storedUserIDKey = [self storedUserIDKey];
  NSString *randomUUID = [self randomUUID];
  
  OCMStub([self.mockLocalStorage loadStringForKey:storedUserIDKey]).andReturn(randomUUID);
  
  OCMExpect([self.mockLocalStorage loadStringForKey:storedUserIDKey]);
  
  // when
  NSString *resultUserID = [self.service obtainUserID];
  
  // then
  OCMVerify([self.mockLocalStorage loadStringForKey:storedUserIDKey]);
  XCTAssertTrue([resultUserID isEqualToString:randomUUID]);
}

- (void)testDeleteUser {
  // given
  NSString *storedUserIDKey = [self storedUserIDKey];
  NSString *originalUserIDKey = [self originalUserIDKey];
  
  OCMExpect([self.mockLocalStorage removeObjectForKey:storedUserIDKey]);
  OCMExpect([self.mockLocalStorage removeObjectForKey:originalUserIDKey]);
  
  // when
  [self.service deleteUser];
  
  // then
  OCMVerify([self.mockLocalStorage removeObjectForKey:storedUserIDKey]);
  OCMVerify([self.mockLocalStorage removeObjectForKey:originalUserIDKey]);
}

- (void)testStoreIdentity {
  // given
  NSString *testID = @"some_test_id";
  NSString *key = @"com.qonversion.keys.storedUserID";
  
  OCMExpect([self.mockLocalStorage setString:testID forKey:key]);
  
  // when
  [self.service storeIdentity:testID];
  
  // then
  OCMVerifyAll(self.mockLocalStorage);
}

#pragma mark - Helpers

- (NSString *)storedUserIDKey {
  return @"com.qonversion.keys.storedUserID";
}

- (NSString *)originalUserIDKey {
  return @"com.qonversion.keys.originalUserID";
}

- (NSString *)randomUUID {
  return @"some-random-uuid";
}

- (NSString *)formattedRandomUUID {
  return @"QON_somerandomuuid";
}

- (id)mockUUIDWithString:(NSString *)uuidString {
  id uuidMock = OCMClassMock([NSUUID class]);
  OCMStub([uuidMock new]).andReturn(uuidMock);
  OCMStub([uuidMock UUIDString]).andReturn(uuidString);
}

@end
