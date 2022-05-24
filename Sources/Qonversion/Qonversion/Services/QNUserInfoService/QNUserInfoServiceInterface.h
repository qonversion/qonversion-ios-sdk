//
//  QNUserInfoServiceInterface.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 18.03.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QNLaunchResult.h"

@protocol QNUserInfoServiceInterface <NSObject>

- (void)obtainUserInfo:(QNUserInfoCompletionHandler)completion;
- (NSString *)obtainUserID;
- (void)storeIdentityResult:(NSString *)userID;
- (void)storeCustomUserID:(NSString *)userID;
- (BOOL)logoutIfNeeded;

@end
