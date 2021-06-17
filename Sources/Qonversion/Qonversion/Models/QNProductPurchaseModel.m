//
//  QNProductPurchaseModel.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 07.06.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QNProductPurchaseModel.h"
#import "QNProduct.h"
#import "QNExperimentInfo.h"

@implementation QNProductPurchaseModel

- (instancetype)initWithProduct:(QNProduct *)product experimentInfo:(QNExperimentInfo * _Nullable)experimentInfo {
  self = [super init];
  
  if (self) {
    _product = product;
    _experimentInfo = experimentInfo;
  }
  
  return self;
}

@end
