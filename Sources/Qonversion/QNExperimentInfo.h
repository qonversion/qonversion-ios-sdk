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

@interface QNExperimentInfo : NSObject

@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, strong) QNExperimentGroup *group;

@end

NS_ASSUME_NONNULL_END
