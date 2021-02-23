//
//  QNOfferings+Protected.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 05.01.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QNOfferings.h"

NS_ASSUME_NONNULL_BEGIN

@interface QNOfferings (Protected)

- (instancetype)initWithMainOffering:(QNOffering *)offering availableOfferings:(NSArray<QNOffering *> *)availableOfferings;

@end

NS_ASSUME_NONNULL_END
