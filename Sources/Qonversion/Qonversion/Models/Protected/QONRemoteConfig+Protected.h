//
//  QONRemoteConfig+Protected.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 13.06.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#import <Qonversion/Qonversion.h>

@class QONExperiment;

NS_ASSUME_NONNULL_BEGIN

@interface QONRemoteConfig ()

- (instancetype)initWithPayload:(NSDictionary *)payload experiment:(QONExperiment *)experiment;

@end

NS_ASSUME_NONNULL_END
