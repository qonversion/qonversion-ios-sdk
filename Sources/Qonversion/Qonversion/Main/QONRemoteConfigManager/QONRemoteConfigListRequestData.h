//
//  QONRemoteConfigListRequestData.h
//  Qonversion
//
//  Created by Kamo Spertsyan on 01.04.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QONLaunchResult.h"

@interface QONRemoteConfigListRequestData : NSObject

@property (nonatomic, strong, nullable) NSArray<NSString *> *contextKeys;
@property (nonatomic, assign) BOOL includeEmptyContextKey;
@property (nonatomic, strong, nonnull) QONRemoteConfigListCompletionHandler completion;

- (instancetype)initWithCompletion:(QONRemoteConfigListCompletionHandler)completion;

- (instancetype)initWithContextKeys:(NSArray<NSString *> *)contextKeys includeEmptyContextKey:(BOOL)includeEmptyContextKey completion:(QONRemoteConfigListCompletionHandler)completion;

@end
