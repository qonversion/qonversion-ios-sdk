//
//  QNOffering+Protected.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 05.01.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QNOffering.h"

NS_ASSUME_NONNULL_BEGIN

@interface QNOffering (Protected)

- (instancetype)initWithIdentifier:(NSString *)identifier tag:(QNOfferingTag)tag products:(NSArray<QNProduct *> *)products experimentInfo:(QNExperimentInfo * _Nullable)experimentInfo;

@end

NS_ASSUME_NONNULL_END
