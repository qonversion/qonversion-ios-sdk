//
//  QNOffering.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 05.01.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QNOffering.h"
#import "QNProduct.h"

@interface QNOffering ()

@property (nonatomic, copy) NSDictionary<NSString *, QNProduct *> *productsMap;

@end

@implementation QNOffering

- (instancetype)initWithIdentifier:(NSString *)identifier tag:(QNOfferingTag)tag products:(NSArray<QNProduct *> *)products {
  self = [super init];
  
  if (self) {
    _identifier = identifier;
    _tag = tag;
    _products = products;
    
    [self configureMapForProducts:products];
  }
  
  return self;
}

- (void)configureMapForProducts:(NSArray<QNProduct *> *)products {
  NSMutableDictionary *productsMap = [NSMutableDictionary new];
  
  for (QNProduct *product in products) {
    productsMap[product.qonversionID] = product;
  }
  
  _productsMap = [productsMap copy];
}

- (nullable QNProduct *)productForIdentifier:(NSString *)productIdentifier {
  return self.productsMap[productIdentifier];
}

- (NSString *)description {
  NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: ", NSStringFromClass([self class])];
  
  [description appendFormat:@"id=%@,\n", self.identifier];
  [description appendFormat:@"tag=%@ (enum value = %li),\n", [self prettyTag], (long) self.tag];
  [description appendFormat:@"products=%@\n", self.products];
  [description appendString:@">"];
  
  return [description copy];
}

- (NSString *)prettyTag {
  NSString *result;
  
  switch (self.tag) {
    case QNOfferingTagMain:
      result = @"main"; break;
      
    default:
      result = @"none";
      break;
  }
  
  return result;
}

@end
