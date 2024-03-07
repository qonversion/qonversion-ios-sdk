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

@interface QONRemoteConfigLoadingState : NSObject

@property (nonatomic, strong) QONRemoteConfig * _Nullable loadedConfig;
@property (nonatomic, strong) NSMutableArray<QONRemoteConfigCompletionHandler> * _Nonnull completions;
@property (nonatomic, assign) BOOL isInProgress;

@end
