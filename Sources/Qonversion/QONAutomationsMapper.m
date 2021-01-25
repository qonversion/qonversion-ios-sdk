//
//  QONAutomationsMapper.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.12.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import "QONAutomationsMapper.h"
#import "QONAutomationsScreen.h"
#import "QNErrors.h"
#import "QNUserActionPoint.h"

@implementation QONAutomationsMapper

- (nullable QONAutomationsScreen *)mapScreen:(NSDictionary *)dict {
  NSDictionary *data = [self getDataFromObject:dict];
  NSString *htmlString = data[@"body"];
  QONAutomationsScreen *screen;
  
  if (htmlString) {
    screen = [[QONAutomationsScreen alloc] initWithHtmlString:htmlString];
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

- (NSArray<QNUserActionPoint *> *)mapUserActionPoints:(NSDictionary *)dict {
  NSMutableArray *actionPoints = [NSMutableArray new];
  NSDictionary *data = [self getDataFromObject:dict];
  NSArray *actionItems = data[@"items"];
  
  for (NSDictionary *action in actionItems) {
    NSNumber *date = action[@"created"];
    NSDate *createDate = [NSDate dateWithTimeIntervalSince1970:date.doubleValue];
    NSString *screenId = action[@"data"][@"screen"];
    
    if ([screenId isKindOfClass:[NSString class]] && screenId.length > 0 && createDate) {
      QNUserActionPoint *actionPoint = [[QNUserActionPoint alloc] initWithScreenId:screenId createDate:createDate];
      
      [actionPoints addObject:actionPoint];
    }
  }
  
  return [actionPoints copy];
}

- (NSDictionary *)getDataFromObject:(NSDictionary *)obj {
  NSDictionary *temp = obj[@"data"];
  
  NSDictionary *result = [temp isKindOfClass:[NSDictionary class]] ? temp : nil;
  
  return result;
}

@end
