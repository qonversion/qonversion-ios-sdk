//
//  QONAutomationsEvent.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.07.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QONAutomationsEvent.h"

@implementation QONAutomationsEvent

- (instancetype)initWithType:(QONAutomationsEventType)type date:(NSDate *)date {
  self = [super init];
  
  if (self) {
    _type = type;
    _date = date;
  }
  
  return self;
}

@end
