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
  [description appendFormat:@"parameters=%@,\n", self.parameters];
  [description appendString:@">"];
  
  return [description copy];
}

- (NSString *)prettyType {
  NSString *result = @"unknown";
  
  switch (self.type) {
    case QONActionResultTypeUnknown:
      result = @"unknown"; break;
    
    case QONActionResultTypeURL:
      result = @"link"; break;
    
    case QONActionResultTypeDeeplink:
      result = @"deeplink"; break;
      
    case QONActionResultTypeNavigation:
      result = @"navigation"; break;
      
    case QONActionResultTypePurchase:
      result = @"purchase"; break;
      
    case QONActionResultTypeRestore:
      result = @"restore purchases"; break;
      
    case QONActionResultTypeClose:
      result = @"close"; break;
      
    case QONActionResultTypeCloseAll:
      result = @"close all"; break;
      
    default:
      break;
  }
  
  return result;
}

@end
