//
//  QONActionResult.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import "QONActionResult.h"

@implementation QONActionResult

- (NSString *)description {
  NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: ", NSStringFromClass([self class])];
  
  [description appendFormat:@"type=%@ (enum value = %li),\n", [self prettyType], (long) self.type];
  [description appendFormat:@"value=%@,\n", self.value];
  [description appendString:@">"];
  
  return [description copy];
}

- (NSString *)prettyType {
  NSString *result = @"unknown";
  
  switch (self.type) {
    case QONActionTypeUnknown:
      result = @"unknown"; break;
    
    case QONActionTypeURL:
      result = @"link"; break;
    
    case QONActionTypeDeeplink:
      result = @"deeplink"; break;
      
    case QONActionTypeNavigation:
      result = @"navigation"; break;
      
    case QONActionTypePurchase:
      result = @"purchase"; break;
      
    case QONActionTypeRestore:
      result = @"restore purchases"; break;
      
    case QONActionTypeClose:
      result = @"close"; break;
      
    default:
      break;
  }
  
  return result;
}

@end
