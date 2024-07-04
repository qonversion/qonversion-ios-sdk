//
//  QONFallbackMapper.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 06.06.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class QONFallbackObject, QNMapper, QONRemoteConfigMapper;

NS_ASSUME_NONNULL_BEGIN

@interface QONFallbackMapper : NSObject

- (QONFallbackObject * _Nullable)mapFallbackData:(NSDictionary *)data;

@end

NS_ASSUME_NONNULL_END
