//
//  QONExperiment.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 08.06.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QONExperimentGroup.h"

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(Qonversion.Experiment)
@interface QONExperiment : NSObject

/**
 Experiment identifier
 */
@property (nonatomic, copy, readonly) NSString *identifier;

/**
 Experiment name
 */
@property (nonatomic, copy, readonly) NSString *name;

/**
 Experiment group info
 */
@property (nonatomic, strong, readonly) QONExperimentGroup *group;

@end

NS_ASSUME_NONNULL_END
