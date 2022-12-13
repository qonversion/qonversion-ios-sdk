//
//  QONAutomationsMapper.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.12.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import "QONAutomationsMapper.h"
#import "QONAutomationsScreen.h"
#import "QONErrors.h"
#import "QONUserActionPoint.h"

@implementation QONAutomationsMapper

- (nullable QONAutomationsScreen *)mapScreen:(NSDictionary *)dict {
  NSDictionary *data = [self getDataFromObject:dict];
  NSString *htmlString = data[@"body"];
  NSString *identifier = data[@"id"] ?: @"";
  
  QONAutomationsScreen *screen;
  
  if (htmlString) {
    screen = [[QONAutomationsScreen alloc] initWithIdentifier:identifier htmlString:htmlString];
  }
  
  return screen;
}

- (NSArray<QONUserActionPoint *> *)mapUserActionPoints:(NSDictionary *)dict {
  NSMutableArray *actionPoints = [NSMutableArray new];
  NSDictionary *data = [self getDataFromObject:dict];
  NSArray *actionItems = data[@"items"];
  
  for (NSDictionary *action in actionItems) {
    NSNumber *date = action[@"created"];
    NSDate *createDate = [NSDate dateWithTimeIntervalSince1970:date.doubleValue];
    NSString *screenId = action[@"data"][@"screen"];
    
    if ([screenId isKindOfClass:[NSString class]] && screenId.length > 0 && createDate) {
      QONUserActionPoint *actionPoint = [[QONUserActionPoint alloc] initWithScreenId:screenId createDate:createDate];
      
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
