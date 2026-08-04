//
//  QONRemoteConfig+Protected.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 13.06.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#import "QONRemoteConfig.h"

@class QONExperiment;

NS_ASSUME_NONNULL_BEGIN

@interface QONRemoteConfig ()

- (instancetype)initWithPayload:(nullable NSDictionary *)payload
                      experiment:(nullable QONExperiment *)experiment
                          source:(QONRemoteConfigurationSource *)source;

@end

NS_ASSUME_NONNULL_END
