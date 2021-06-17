//
//  QNExperimentInfo.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 15.01.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class QNExperimentGroup;

NS_SWIFT_NAME(Qonversion.ExperimentInfo)
@interface QNExperimentInfo : NSObject

@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, strong, nullable, readonly) QNExperimentGroup *group;
@property (nonatomic, assign) BOOL attached;

@end

NS_ASSUME_NONNULL_END
