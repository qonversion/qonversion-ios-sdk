//
//  QONRemoteConfigManager.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 21.03.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QONLaunchResult.h"

@class QONRemoteConfigService;

NS_ASSUME_NONNULL_BEGIN

@interface QONRemoteConfigManager : NSObject

@property (nonatomic, strong) QONRemoteConfigService *remoteConfigService;

- (void)launchFinished:(BOOL)finished;
- (void)obtainRemoteConfig:(QONRemoteConfigCompletionHandler)completion;
- (void)userHasBeenChanged;

@end

NS_ASSUME_NONNULL_END
