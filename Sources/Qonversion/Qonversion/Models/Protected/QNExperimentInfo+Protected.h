//
//  QNExperimentInfo+Protected.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 15.01.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QNExperimentInfo.h"

NS_ASSUME_NONNULL_BEGIN

@interface QNExperimentInfo (Protected)

- (instancetype)initWithIdentifier:(NSString *)identifier group:(QNExperimentGroup * _Nullable)group;

@end

NS_ASSUME_NONNULL_END
