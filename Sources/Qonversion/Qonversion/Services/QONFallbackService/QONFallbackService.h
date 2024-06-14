//
//  QONFallbackService.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 06.06.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class QONFallbackObject, QONFallbackMapper;

NS_ASSUME_NONNULL_BEGIN

@interface QONFallbackService : NSObject

- (QONFallbackObject * _Nullable)obtainFallbackData;

@end

NS_ASSUME_NONNULL_END
