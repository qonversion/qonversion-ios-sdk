//
//  QONRemoteConfigListRequestData.h
//  Qonversion
//
//  Created by Kamo Spertsyan on 01.04.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QONLaunchResult.h"

NS_ASSUME_NONNULL_BEGIN

@interface QONRemoteConfigListRequestData : NSObject

@property (nonatomic, copy, nullable) NSArray<NSString *> *contextKeys;
@property (nonatomic, assign) BOOL includeEmptyContextKey;
@property (nonatomic, copy, nonnull) QONRemoteConfigListCompletionHandler completion;

- (instancetype)initWithCompletion:(QONRemoteConfigListCompletionHandler)completion;

- (instancetype)initWithContextKeys:(NSArray<NSString *> *)contextKeys includeEmptyContextKey:(BOOL)includeEmptyContextKey completion:(QONRemoteConfigListCompletionHandler)completion;

@end

NS_ASSUME_NONNULL_END
