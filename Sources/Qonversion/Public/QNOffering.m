//
//  QNOffering.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 05.01.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QNOffering.h"
#import "QNProduct.h"
#import "QNExperimentInfo.h"

@interface QNOffering ()

@property (nonatomic, copy) NSDictionary<NSString *, QNProduct *> *productsMap;
@property (nonatomic, copy, readwrite) NSArray<QNProduct *> *products;

@end

@implementation QNOffering

- (instancetype)initWithIdentifier:(NSString *)identifier
                               tag:(QNOfferingTag)tag
                          products:(NSArray<QNProduct *> *)products
                    experimentInfo:(QNExperimentInfo * _Nullable)experimentInfo {
  self = [super init];
  
  if (self) {
    _identifier = identifier;
    _tag = tag;
    _products = products;
    _experimentInfo = experimentInfo;
    
    [self configureMapForProducts:products];
  }
  
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super init];
  
  if (self) {
    _identifier = [coder decodeObjectForKey:NSStringFromSelector(@selector(identifier))];
    _tag = [coder decodeIntForKey:NSStringFromSelector(@selector(tag))];
    _products = [coder decodeObjectForKey:NSStringFromSelector(@selector(products))];
    _experimentInfo = [coder decodeObjectForKey:NSStringFromSelector(@selector(experimentInfo))];
  }
  
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeObject:_identifier forKey:NSStringFromSelector(@selector(identifier))];
  [coder encodeInteger:_tag forKey:NSStringFromSelector(@selector(tag))];
  [coder encodeObject:_products forKey:NSStringFromSelector(@selector(products))];
  [coder encodeObject:_experimentInfo forKey:NSStringFromSelector(@selector(experimentInfo))];
}

- (void)configureMapForProducts:(NSArray<QNProduct *> *)products {
  NSMutableDictionary *productsMap = [NSMutableDictionary new];
  
  for (QNProduct *product in products) {
    productsMap[product.qonversionID] = product;
  }
  
  _productsMap = [productsMap copy];
}

- (NSDictionary<NSString *,QNProduct *> *)productsMap {
  [self sendNotificationIfNeeded];
  
  return _productsMap;
}

- (NSArray<QNProduct *> *)products {
  [self sendNotificationIfNeeded];
  
  return _products;
}

- (void)sendNotificationIfNeeded {
  if (self.experimentInfo && !self.experimentInfo.attached) {
    NSNotification *notification = [NSNotification notificationWithName:kOfferingByIDWasCalledNotificationName object:self];
    [[NSNotificationCenter defaultCenter] postNotification:notification];
  }
}

- (nullable QNProduct *)productForIdentifier:(NSString *)productIdentifier {
  return self.productsMap[productIdentifier];
}

- (NSString *)description {
  NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: ", NSStringFromClass([self class])];
  
  [description appendFormat:@"id=%@,\n", self.identifier];
  [description appendFormat:@"tag=%@ (enum value = %li),\n", [self prettyTag], (long) self.tag];
  [description appendFormat:@"products=%@\n", self.products];
  [description appendFormat:@"experimentInfo=%@\n", self.experimentInfo];
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
