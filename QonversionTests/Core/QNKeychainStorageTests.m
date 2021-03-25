//
//  QNKeychainStorageTests.m
//  QonversionTests
//
//  Created by Surik Sarkisyan on 19.03.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>

#import "XCTestCase+Unmock.h"

#import "QNKeychainStorage.h"
#import "QNKeychain.h"

@interface QNKeychainStorageTests : XCTestCase

@property (nonatomic, strong) QNKeychainStorage *storage;
@property (nonatomic, strong) QNKeychain *mockKeychain;

@end

@implementation QNKeychainStorageTests

- (void)setUp {
  self.storage = [QNKeychainStorage new];
  self.mockKeychain = OCMStrictClassMock([QNKeychain class]);
  
  self.storage.keychain = self.mockKeychain;
}

- (void)tearDown {
  self.storage = nil;
  
  [self unmock:self.mockKeychain];
}

- (void)testObtainUserID_empty {
  // given
  NSUInteger attemptsCount = 5;
  NSString *key = [self keychainKey];
  
  OCMStub([self.mockKeychain stringForKey:key]).andReturn(nil);
  
  OCMExpect([self.mockKeychain stringForKey:key]);
  
  // when
  NSString *userID = [self.storage obtainUserID:attemptsCount];
  
  // then
  OCMVerify(times(attemptsCount + 1), [self.mockKeychain stringForKey:key]);
  XCTAssertNil(userID);
}

- (void)testObtainUserID_notEmpty {
  // given
  NSUInteger attemptsCount = 5;
  NSString *randomUID = @"someRAndOMUid";
  NSString *key = [self keychainKey];
  
  OCMStub([self.mockKeychain stringForKey:key]).andReturn(randomUID);
  
  OCMExpect([self.mockKeychain stringForKey:key]);
  
  // when
  NSString *userID = [self.storage obtainUserID:attemptsCount];
  
  // then
  OCMVerify([self.mockKeychain stringForKey:key]);
  XCTAssertTrue([userID isEqualToString:randomUID]);
}

- (void)testResetUserID {
  // given
  NSString *key = [self keychainKey];
  OCMExpect([self.mockKeychain deleteValueForKey:key]);
  
  // when
  [self.storage resetUserID];
  
  // then
  OCMVerifyAll(self.mockKeychain);
}

#pragma mark - Private

- (NSString *)keychainKey {
  return @"Qonversion.Keeper.userID";
}

@end
