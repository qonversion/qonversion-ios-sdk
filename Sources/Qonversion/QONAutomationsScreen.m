//
//  QONAutomationsScreen.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.12.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import "QONAutomationsScreen.h"

@interface QONAutomationsScreen ()

@property (nonatomic, copy, readwrite) NSString *screenID;
@property (nonatomic, copy, readwrite) NSString *htmlString;

@end

@implementation QONAutomationsScreen

- (instancetype)initWithIdentifier:(NSString *)identifier htmlString:(NSString *)html {
  self = [super init];
  if (self) {
    _screenID = identifier;
    _htmlString = html;
  }
  return self;
}

@end
