//
//  QNIdentityManager.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 22.03.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "QNIdentityManagerInterface.h"

@protocol QNIdentityServiceInterface, QNUserInfoServiceInterface;

NS_ASSUME_NONNULL_BEGIN

@interface QNIdentityManager : NSObject <QNIdentityManagerInterface>

@property (nonatomic, strong) id<QNIdentityServiceInterface> identityService;
@property (nonatomic, strong) id<QNUserInfoServiceInterface> userInfoService;

@end

NS_ASSUME_NONNULL_END
