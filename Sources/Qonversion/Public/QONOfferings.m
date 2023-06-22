//
//  QONOfferings.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 05.01.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QONOfferings.h"
#import "QONOffering.h"
#import "QONOfferings+Protected.h"

@interface QONOfferings ()

@property (nonatomic, copy) NSDictionary<NSString *, QONOffering *> *offeringsMap;

@end

@implementation QONOfferings

- (instancetype)initWithMainOffering:(QONOffering *)offering availableOfferings:(NSArray<QONOffering *> *)availableOfferings {
  self = [super init];
  
  if (self) {
    _main = offering;
    _availableOfferings = availableOfferings;
    [self configureMapForOfferings:availableOfferings];
  }
  
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super init];
  
  if (self) {
    _availableOfferings = [coder decodeObjectForKey:NSStringFromSelector(@selector(availableOfferings))];
    _main = [coder decodeObjectForKey:NSStringFromSelector(@selector(main))];
  }
  
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeObject:_availableOfferings forKey:NSStringFromSelector(@selector(availableOfferings))];
  [coder encodeObject:_main forKey:NSStringFromSelector(@selector(main))];
}

- (void)configureMapForOfferings:(NSArray<QONOffering *> *)offerings {
  NSMutableDictionary *offeringsDict = [NSMutableDictionary new];
  
  for (QONOffering *offering in offerings) {
    offeringsDict[offering.identifier] = offering;
  }
  
  _offeringsMap = [offeringsDict copy];
}

- (nullable QONOffering *)offeringForIdentifier:(nonnull NSString *)offeringIdentifier {
  return self.offeringsMap[offeringIdentifier];
}

@end
