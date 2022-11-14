//
//  QONOfferings+Protected.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 05.01.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QONOfferings.h"

NS_ASSUME_NONNULL_BEGIN

@interface QONOfferings (Protected)

- (instancetype)initWithMainOffering:(QONOffering *)offering availableOfferings:(NSArray<QONOffering *> *)availableOfferings;

@end

NS_ASSUME_NONNULL_END
