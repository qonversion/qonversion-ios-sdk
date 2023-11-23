//
//  QONExperiment+Protected.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 08.06.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#import "QONExperiment.h"

NS_ASSUME_NONNULL_BEGIN

@interface QONExperiment ()

- (instancetype)initWithIdentifier:(NSString *)identifier
                              name:(NSString *)name
                             group:(QONExperimentGroup *)group;

@end

NS_ASSUME_NONNULL_END
