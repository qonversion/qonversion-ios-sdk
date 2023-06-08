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

@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) QONExperimentGroup *group;

@end

NS_ASSUME_NONNULL_END
