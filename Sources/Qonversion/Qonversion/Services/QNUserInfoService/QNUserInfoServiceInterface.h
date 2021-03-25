//
//  QNUserInfoServiceInterface.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 18.03.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol QNUserInfoServiceInterface <NSObject>

- (NSString *)obtainUserID;
- (void)storeIdentity:(NSString *)userID;
- (void)logout;

@end
