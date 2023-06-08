//
//  QONExperimentGroup.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 15.01.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, QONExperimentGroupType) {
  QONExperimentGroupTypeUnknown = -1,
  QONExperimentGroupTypeControl = 0,
  QONExperimentGroupTypeTreatment = 1
} NS_SWIFT_NAME(Qonversion.ExperimentGroupType);

NS_SWIFT_NAME(Qonversion.ExperimentGroup)
@interface QONExperimentGroup : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) QONExperimentGroupType type;

@end

NS_ASSUME_NONNULL_END
