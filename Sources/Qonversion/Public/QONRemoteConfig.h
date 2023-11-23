//
//  QONRemoteConfig.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 24.03.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QONExperiment.h"
#import "QONRemoteConfigurationSource.h"

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(Qonversion.RemoteConfig)
@interface QONRemoteConfig : NSObject

/**
 Remote config payload
 */
@property (nonatomic, copy, nullable, readonly) NSDictionary *payload;

/**
 Experiment info
 */
@property (nonatomic, strong, nullable, readonly) QONExperiment *experiment;

/**
 Remote configuration source
 */
@property (nonatomic, strong, nonnull, readonly) QONRemoteConfigurationSource *source;

@end

NS_ASSUME_NONNULL_END
