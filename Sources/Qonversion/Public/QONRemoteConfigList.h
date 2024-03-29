//
//  QONRemoteConfigList.h
//  Qonversion
//
//  Created by Kamo Spertsyan on 27.03.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QONRemoteConfig.h"

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(Qonversion.RemoteConfigList)
@interface QONRemoteConfigList : NSObject

@property (nonatomic, copy) NSArray<QONRemoteConfig *> *remoteConfigs;

- (QONRemoteConfig *_Nullable)remoteConfigForContextKey:(NSString *)key;
- (QONRemoteConfig *_Nullable)remoteConfigForEmptyContextKey;

@end

NS_ASSUME_NONNULL_END
