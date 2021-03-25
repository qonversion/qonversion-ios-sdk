//
//  QNUserInfoService.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 18.03.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QNUserInfoService.h"
#import "QNUserInfoServiceInterface.h"
#import "QNLocalStorage.h"
#import "QNInternalConstants.h"
#import "QNKeychainStorage.h"

static NSUInteger const kKeychainAttemptsCount = 3;

@implementation QNUserInfoService

- (NSString *)obtainUserID {
  NSString *cachedUserID = [self.localStorage loadStringForKey:kKeyQUserDefaultsUserID];
  NSString *resultUserID = cachedUserID;
  
  if (resultUserID.length == 0) {
    resultUserID = [self.keychainStorage obtainUserID:kKeychainAttemptsCount];
    [self.keychainStorage resetUserID];
  }
  
  if (resultUserID.length == 0) {
    resultUserID = [self generateRandomUserID];
  }
  
  if (cachedUserID.length == 0) {
    [self.localStorage setString:resultUserID forKey:kKeyQUserDefaultsUserID];
    [self.localStorage setString:resultUserID forKey:kKeyQUserDefaultsOriginalUserID];
  }
  
  return resultUserID;
}

- (void)storeIdentity:(NSString *)userID {
  [self.localStorage setString:userID forKey:kKeyQUserDefaultsUserID];
}

- (void)logout {
  NSString *originalUserID = [self.localStorage loadStringForKey:kKeyQUserDefaultsOriginalUserID];
  
  [self.localStorage setString:originalUserID forKey:kKeyQUserDefaultsUserID];
}

#pragma mark - Private

- (NSString *)generateRandomUserID {
  NSUUID *uuid = [NSUUID new];
  NSString *uuidString = [uuid.UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""];
  NSString *qonversionUID = [NSString stringWithFormat:@"%@%@%@", kKeyQUserIDPrefix, kKeyQUserIDSeparator, uuidString.lowercaseString];
  
  return qonversionUID;
}

@end
