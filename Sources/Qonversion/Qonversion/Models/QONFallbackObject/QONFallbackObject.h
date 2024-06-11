//
//  QONFallbackObject.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 06.06.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class QONProduct, QONOfferings, QONRemoteConfig, QONRemoteConfigList;

NS_ASSUME_NONNULL_BEGIN

@interface QONFallbackObject : NSObject

@property (nonatomic, copy, nullable) NSDictionary<NSString *, QONProduct *> *products;

@property (nonatomic, strong, nullable) QONOfferings *offerings;

@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSArray *> *productsEntitlementsRelation;

@property (nonatomic, strong, nullable) QONRemoteConfig *remoteConfig;

@property (nonatomic, strong, nullable) QONRemoteConfigList *remoteConfigList;

@end

NS_ASSUME_NONNULL_END
