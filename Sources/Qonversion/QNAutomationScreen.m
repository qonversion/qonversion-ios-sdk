//
//  QNAutomationScreen.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.12.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import "QNAutomationScreen.h"

@interface QNAutomationScreen ()

@property (nonatomic, copy, readwrite) NSString *htmlString;

@end

@implementation QNAutomationScreen

- (instancetype)initWithHtmlString:(NSString *)html {
  self = [super init];
  if (self) {
    _htmlString = html;
  }
  return self;
}

@end
