//
//  QONFallbacksService.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 06.06.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class QONFallbackObject, QONFallbacksMapper;

NS_ASSUME_NONNULL_BEGIN

@interface QONFallbacksService : NSObject

- (QONFallbackObject * _Nullable)obtainFallbackData;

@end

NS_ASSUME_NONNULL_END
