//
//  QNProductPurchaseModel.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 07.06.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class QNProduct, QNExperimentInfo;

NS_ASSUME_NONNULL_BEGIN

@interface QNProductPurchaseModel : NSObject

@property (nonatomic, strong) QNProduct *product;
@property (nonatomic, strong, nullable) QNExperimentInfo *experimentInfo;

- (instancetype)initWithProduct:(QNProduct *)product experimentInfo:(QNExperimentInfo * _Nullable)experimentInfo;

@end

NS_ASSUME_NONNULL_END
