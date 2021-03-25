//
//  QNServicesAssembly.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 19.03.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol QNUserInfoServiceInterface, QNIdentityManagerInterface;

NS_ASSUME_NONNULL_BEGIN

@interface QNServicesAssembly : NSObject

- (id<QNUserInfoServiceInterface>)userInfoService;
- (id<QNIdentityManagerInterface>)identityManager;

@end

NS_ASSUME_NONNULL_END
