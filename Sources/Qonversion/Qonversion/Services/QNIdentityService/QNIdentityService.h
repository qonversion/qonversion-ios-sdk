//
//  QNIdentityService.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 22.03.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "QNIdentityServiceInterface.h"

@class QNAPIClient;

NS_ASSUME_NONNULL_BEGIN

@interface QNIdentityService : NSObject <QNIdentityServiceInterface>

@property (nonatomic, strong) QNAPIClient *apiClient;

@end

NS_ASSUME_NONNULL_END
