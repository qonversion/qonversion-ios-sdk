//
//  QONAutomationsEvent.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.07.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QONAutomationsEvent.h"

@interface QONAutomationsEvent ()

@property (nonatomic, copy, nullable) NSString *productId;

@end

@implementation QONAutomationsEvent

- (instancetype)initWithType:(QONAutomationsEventType)type date:(NSDate *)date productId:(NSString *)productId {
  self = [super init];
  
  if (self) {
    _type = type;
    _date = date;
    _productId = productId;
  }
  
  return self;
}

@end
