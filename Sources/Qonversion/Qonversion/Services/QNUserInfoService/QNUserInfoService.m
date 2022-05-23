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
#import "QNUserInfoMapperInterface.h"
#import "QNAPIClient.h"

static NSUInteger const kKeychainAttemptsCount = 3;

@implementation QNUserInfoService

- (void)obtainUserInfo:(QNUserInfoCompletionHandler)completion {
  NSString *userID = [self obtainUserID];
  
  __block __weak QNUserInfoService *weakSelf = self;
  [self.apiClient userInfoRequestWithID:userID completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
    QNUser *user = [weakSelf.mapper mapUserInfo:dict];
    completion(user, error);
  }];
}

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
  }
  
  return resultUserID;
}

- (void)storeIdentity:(NSString *)userID {
  [self.localStorage setString:userID forKey:kKeyQUserDefaultsUserID];
}

- (void)storeCustomUserID:(NSString *)userID {
  [self.localStorage setString:userID forKey:kKeyQUserDefaultsIdentityUserID];
}

- (BOOL)logoutIfNeeded {
  NSString *currentIdentityUserID = [self.localStorage loadStringForKey:kKeyQUserDefaultsIdentityUserID];
  if (currentIdentityUserID.length > 0) {
    [self.localStorage removeObjectForKey:kKeyQUserDefaultsIdentityUserID];
    
    NSString *userID = [self generateRandomUserID];
    [self.localStorage setString:userID forKey:kKeyQUserDefaultsUserID];
    
    return YES;
  } else {
    return NO;
  }
}

#pragma mark - Private

- (NSString *)generateRandomUserID {
  NSUUID *uuid = [NSUUID new];
  NSString *uuidString = [uuid.UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""];
  NSString *qonversionUID = [NSString stringWithFormat:@"%@%@%@", kKeyQUserIDPrefix, kKeyQUserIDSeparator, uuidString.lowercaseString];
  
  return qonversionUID;
}

@end
