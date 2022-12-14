//
//  QNProductPurchaseModel.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 07.06.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class QONProduct, QONExperimentInfo;

NS_ASSUME_NONNULL_BEGIN

@interface QNProductPurchaseModel : NSObject

@property (nonatomic, strong) QONProduct *product;
@property (nonatomic, strong, nullable) QONExperimentInfo *experimentInfo;

- (instancetype)initWithProduct:(QONProduct *)product experimentInfo:(QONExperimentInfo * _Nullable)experimentInfo;

@end

NS_ASSUME_NONNULL_END
