//
//  QONRemoteConfigMapper.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 12.06.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class QONRemoteConfig;

NS_ASSUME_NONNULL_BEGIN

@interface QONRemoteConfigMapper : NSObject

- (QONRemoteConfig * _Nullable)mapRemoteConfig:(NSDictionary *)remoteConfigData;

@end

NS_ASSUME_NONNULL_END
