//
//  QONExperimentGroup+Protected.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 15.01.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QONExperimentGroup.h"

NS_ASSUME_NONNULL_BEGIN

@interface QONExperimentGroup (Protected)

- (instancetype)initWithIdentifier:(NSString *)identifier type:(QONExperimentGroupType)type name:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
