//
//  QONRemoteConfigLoadingState.h
//  Qonversion
//
//  Created by Kamo Spertsyan on 07.03.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QONLaunchResult.h"

@interface QONRemoteConfigLoadingState : NSObject

@property (nonatomic, strong, nullable) QONRemoteConfig *loadedConfig;
@property (nonatomic, strong, nonnull) NSMutableArray<QONRemoteConfigCompletionHandler> *completions;
@property (nonatomic, assign) BOOL isInProgress;

@end
