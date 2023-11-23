//
//  QNServicesAssembly.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 19.03.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol QNUserInfoServiceInterface, QNIdentityManagerInterface, QNLocalStorage;

NS_ASSUME_NONNULL_BEGIN

@interface QNServicesAssembly : NSObject

- (instancetype)initWithCustomUserDefaults:(NSUserDefaults *)userDefaults;

- (id<QNUserInfoServiceInterface>)userInfoService;
- (id<QNIdentityManagerInterface>)identityManager;
- (id<QNLocalStorage>)localStorage;

@end

NS_ASSUME_NONNULL_END
