//
//  QONUserActionPoint.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 28.12.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import "QONUserActionPoint.h"

@implementation QONUserActionPoint

- (instancetype)initWithScreenId:(NSString *)screenId createDate:(NSDate *)createDate {
  self = [super init];
  if (self) {
    _screenId = screenId;
    _createDate = createDate;
  }
  return self;
}

@end
