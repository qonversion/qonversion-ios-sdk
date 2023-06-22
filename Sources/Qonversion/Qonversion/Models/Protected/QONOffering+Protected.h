//
//  QONOffering+Protected.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 05.01.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QONOffering.h"

NS_ASSUME_NONNULL_BEGIN

@interface QONOffering (Protected)

- (instancetype)initWithIdentifier:(NSString *)identifier tag:(QONOfferingTag)tag products:(NSArray<QONProduct *> *)products;

@end

NS_ASSUME_NONNULL_END
