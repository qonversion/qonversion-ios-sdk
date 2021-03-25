//
//  QNKeychainStorage.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 18.03.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QNKeychainStorage.h"
#import "QNInternalConstants.h"
#import "QNKeychain.h"

@implementation QNKeychainStorage

- (NSString *_Nullable)obtainUserID:(NSUInteger)maxAttemptsCount {
  NSString *userID = [self.keychain stringForKey:kKeyQKeyChainUserID];
  
  if (userID.length == 0 && maxAttemptsCount > 0) {
    return [self obtainUserID:maxAttemptsCount - 1];
  }
  
  return userID.length > 0 ? userID : nil;
}

- (void)resetUserID {
  [self.keychain deleteValueForKey:kKeyQKeyChainUserID];
}

@end
