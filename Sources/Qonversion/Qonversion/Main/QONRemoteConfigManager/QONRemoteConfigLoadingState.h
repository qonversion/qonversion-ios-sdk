//
//  QONRemoteConfigLoadingState.h
//  Qonversion
//
//  Created by Kamo Spertsyan on 07.03.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QONLaunchResult.h"
#import "QONExperiment.h"

NS_ASSUME_NONNULL_BEGIN

@interface QONRemoteConfigLoadingState : NSObject

@property (nonatomic, strong) QONRemoteConfig *loadedConfig;
@property (nonatomic, strong) NSMutableArray<QONRemoteConfigCompletionHandler> *completions;
@property (nonatomic, assign) BOOL isInProgress;

@end

NS_ASSUME_NONNULL_END
