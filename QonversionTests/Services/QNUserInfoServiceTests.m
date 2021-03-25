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
#import "QNKeychainStorageInterface.h"
#import "QNLocalStorage.h"

@interface QNUserInfoServiceTests : XCTestCase

@property (nonatomic, strong) QNUserInfoService *service;
@property (nonatomic, strong) id<QNKeychainStorageInterface> mockKeychainStorage;
@property (nonatomic, strong) id<QNLocalStorage> mockLocalStorage;

@end

@implementation QNUserInfoServiceTests

- (void)setUp {
  [super setUp];
  
  self.service = [QNUserInfoService new];
  self.mockKeychainStorage = OCMStrictProtocolMock(@protocol(QNKeychainStorageInterface));
  self.mockLocalStorage = OCMStrictProtocolMock(@protocol(QNLocalStorage));
  
  self.service.keychainStorage = self.mockKeychainStorage;
  self.service.localStorage = self.mockLocalStorage;
}

- (void)tearDown {
  self.service = nil;

  [self unmock:self.mockKeychainStorage];
  [self unmock:self.mockLocalStorage];
    
  [super tearDown];
}

- (void)testObtainUserID_userDefaultsEmpty_keychainEmpty {
  // given
  NSString *storedUserIDKey = [self storedUserIDKey];
  NSString *originalUserIDKey = [self originalUserIDKey];
  NSString *randomUUID = [self randomUUID];
  NSString *formattedUUID = [self formattedRandomUUID];
  
  id mockUUID = [self mockUUIDWithString:randomUUID];
  
  OCMStub([self.mockLocalStorage loadStringForKey:storedUserIDKey]).andReturn(nil);
  OCMStub([self.mockKeychainStorage obtainUserID:3]).andReturn(nil);
  
  OCMExpect([self.mockLocalStorage loadStringForKey:storedUserIDKey]);
  OCMExpect([self.mockKeychainStorage obtainUserID:3]);
  OCMExpect([self.mockKeychainStorage resetUserID]);
  OCMExpect([self.mockLocalStorage setString:formattedUUID forKey:storedUserIDKey]);
  OCMExpect([self.mockLocalStorage setString:formattedUUID forKey:originalUserIDKey]);
  
  // when
  NSString *resultUserID = [self.service obtainUserID];
  
  // then
  OCMVerify([self.mockLocalStorage loadStringForKey:storedUserIDKey]);
  OCMVerify([self.mockKeychainStorage obtainUserID:3]);
  OCMVerify([self.mockKeychainStorage resetUserID]);
  OCMVerify([self.mockLocalStorage setString:formattedUUID forKey:storedUserIDKey]);
  OCMVerify([self.mockLocalStorage setString:formattedUUID forKey:originalUserIDKey]);
  XCTAssertTrue([resultUserID isEqualToString:formattedUUID]);
  
  [self unmock:mockUUID];
}

- (void)testObtainUserID_userDefaultsEmpty_keychainNotEmpty {
  // given
  NSString *storedUserIDKey = [self storedUserIDKey];
  NSString *originalUserIDKey = [self originalUserIDKey];
  NSString *randomUUID = [self randomUUID];
  
  OCMStub([self.mockLocalStorage loadStringForKey:storedUserIDKey]).andReturn(nil);
  OCMStub([self.mockKeychainStorage obtainUserID:3]).andReturn(randomUUID);
  
  OCMExpect([self.mockLocalStorage loadStringForKey:storedUserIDKey]);
  OCMExpect([self.mockKeychainStorage obtainUserID:3]);
  OCMExpect([self.mockKeychainStorage resetUserID]);
  OCMExpect([self.mockLocalStorage setString:randomUUID forKey:storedUserIDKey]);
  OCMExpect([self.mockLocalStorage setString:randomUUID forKey:originalUserIDKey]);
  
  // when
  NSString *resultUserID = [self.service obtainUserID];
  
  // then
  OCMVerify([self.mockLocalStorage loadStringForKey:storedUserIDKey]);
  OCMVerify([self.mockKeychainStorage obtainUserID:3]);
  OCMVerify([self.mockKeychainStorage resetUserID]);
  OCMVerify([self.mockLocalStorage setString:randomUUID forKey:storedUserIDKey]);
  OCMVerify([self.mockLocalStorage setString:randomUUID forKey:originalUserIDKey]);
  XCTAssertTrue([resultUserID isEqualToString:randomUUID]);
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
  OCMExpect([self.mockKeychainStorage resetUserID]);
  
  // when
  [self.service deleteUser];
  
  // then
  OCMVerify([self.mockLocalStorage removeObjectForKey:storedUserIDKey]);
  OCMVerify([self.mockLocalStorage removeObjectForKey:originalUserIDKey]);
  OCMVerify([self.mockKeychainStorage resetUserID]);
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
