//
//  QNScreensMapper.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.12.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import "QNScreensMapper.h"
#import "QNAutomationScreen.h"
#import "QNErrors.h"

@implementation QNScreensMapper

- (nullable QNAutomationScreen *)mapScreen:(NSDictionary *)dict {
  NSString *htmlString = dict[@"data"][@"body"];
  QNAutomationScreen *screen;
  
  if (htmlString) {
    screen = [[QNAutomationScreen alloc] initWithHtmlString:htmlString];
  }
  
  return screen;
}

- (nullable NSError *)mapError:(NSDictionary *)dict {
  NSDictionary *errorDict = dict[@"error"];
  NSString *errorMessage = errorDict[@"message"];
  
  NSError *error;
  
  if (errorMessage.length > 0) {
    NSDictionary *info = @{NSLocalizedDescriptionKey: errorMessage};
    error = [NSError errorWithDomain:keyQNErrorDomain code:QNAPIErrorIncorrectRequest userInfo:info];
  }
  
  return error;
}

@end
