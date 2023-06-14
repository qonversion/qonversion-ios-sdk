//
//  QONRemoteConfig.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 24.03.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QONExperiment.h"

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(Qonversion.RemoteConfig)
@interface QONRemoteConfig : NSObject

@property (nonatomic, copy, nullable, readonly) NSDictionary *payload;
@property (nonatomic, strong, nullable, readonly) QONExperiment *experiment;

@end

NS_ASSUME_NONNULL_END
