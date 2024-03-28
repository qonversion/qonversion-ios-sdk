//
//  QONRemoteConfigList+protected.h
//  Qonversion
//
//  Created by Kamo Spertsyan on 27.03.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

#import "QONRemoteConfigList.h"

@class QONRemoteConfig;

NS_ASSUME_NONNULL_BEGIN

@interface QONRemoteConfigList ()

- (instancetype)initWithRemoteConfigs:(NSArray *)remoteConfigs;

@end

NS_ASSUME_NONNULL_END
