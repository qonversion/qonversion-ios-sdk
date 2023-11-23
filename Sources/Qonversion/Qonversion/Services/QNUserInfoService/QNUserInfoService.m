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
#import "QNUserInfoMapperInterface.h"
#import "QNAPIClient.h"


@implementation QNUserInfoService

- (void)obtainUserInfo:(QONUserInfoCompletionHandler)completion {
  NSString *userID = [self obtainUserID];
  
  __block __weak QNUserInfoService *weakSelf = self;
  [self.apiClient userInfoRequestWithID:userID completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
    QONUser *user = [weakSelf.mapper mapUserInfo:dict];
    completion(user, error);
  }];
}

- (NSString *)obtainUserID {
  NSString *cachedUserID = [self.localStorage loadStringForKey:kKeyQUserDefaultsUserID];
  
  if (cachedUserID.length == 0) {
    cachedUserID = [self generateRandomUserID];
    [self.localStorage setString:cachedUserID forKey:kKeyQUserDefaultsUserID];
    [self.localStorage setString:cachedUserID forKey:kKeyQUserDefaultsOriginalUserID];
  }
  
  return cachedUserID;
}

- (void)storeIdentity:(NSString *)userID {
  [self.localStorage setString:userID forKey:kKeyQUserDefaultsUserID];
}

- (BOOL)logoutIfNeeded {
  NSString *originalUserID = [self.localStorage loadStringForKey:kKeyQUserDefaultsOriginalUserID];
  NSString *defaultUserID = [self.localStorage loadStringForKey:kKeyQUserDefaultsUserID];
  
  if ([originalUserID isEqualToString:defaultUserID]) {
    return NO;
  }
  
  [self.localStorage setString:originalUserID forKey:kKeyQUserDefaultsUserID];
  
  return YES;
}

- (void)deleteUser {
  [self.localStorage removeObjectForKey:kKeyQUserDefaultsUserID];
  [self.localStorage removeObjectForKey:kKeyQUserDefaultsOriginalUserID];
}

- (NSString *)obtainCustomIdentityUserID {
  return [self.localStorage loadStringForKey:kKeyQUserDefaultsIdentityUserID];
}

- (void)storeCustomIdentityUserID:(NSString *)userID {
  [self.localStorage setString:userID forKey:kKeyQUserDefaultsIdentityUserID];
}

#pragma mark - Private

- (NSString *)generateRandomUserID {
  NSUUID *uuid = [NSUUID new];
  NSString *uuidString = [uuid.UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""];
  NSString *qonversionUID = [NSString stringWithFormat:@"%@%@%@", kKeyQUserIDPrefix, kKeyQUserIDSeparator, uuidString.lowercaseString];
  
  return qonversionUID;
}

@end
