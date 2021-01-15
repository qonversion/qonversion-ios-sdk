//
//  QNIntroEligibility.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 14.01.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QNIntroEligibility.h"

@implementation QNIntroEligibility

- (instancetype)initWithStatus:(QNIntroEligibilityStatus)status {
  self = [super init];
  
  if (self) {
    _status = status;
  }
  
  return self;
}

- (NSString *)description {
  NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: ", NSStringFromClass([self class])];
  
  [description appendFormat:@"status=%@ (enum value = %li),\n", [self prettyStatus], (long) self.status];
  [description appendString:@">"];
  
  return [description copy];
}

- (NSString *)prettyStatus {
  NSString *result;
  
  switch (self.status) {
    case QNIntroEligibilityStatusNonIntroProduct:
      result = @"non intro product"; break;
      
    case QNIntroEligibilityStatusIneligible:
      result = @"intro ineligible"; break;
      
    case QNIntroEligibilityStatusEligible:
      result = @"intro eligible"; break;
      
    default:
      result = @"unknown";
      break;
  }
  
  return result;
}

@end
