//
//  QNUserProduct+Protected.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 20.05.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QNUserProduct.h"

NS_ASSUME_NONNULL_BEGIN

@interface QNUserProduct (Protected)

- (instancetype)initWithIdentifier:(NSString *)identifier
                              type:(QNUserProductType)type
                          currency:(NSString *)currency
                             price:(NSInteger)price
                 introductoryPrice:(NSInteger)introductoryPrice
              introductoryDuration:(NSString *)introductoryDuration
                      subscription:(QNSubscription *)subscription
                            object:(NSString *)object;

@end

NS_ASSUME_NONNULL_END
