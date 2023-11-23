//
//  QONScreenPresentationConfiguration.m
//  Qonversion
//
//  Created by Suren Sarkisyan on 20.12.2022.
//  Copyright © 2022 Qonversion Inc. All rights reserved.
//

#import "QONScreenPresentationConfiguration.h"

@implementation QONScreenPresentationConfiguration

+ (instancetype)defaultConfiguration {
  return [[self alloc] initWithPresentationStyle:QONScreenPresentationStyleFullScreen animated:YES];
}

- (instancetype)initWithPresentationStyle:(QONScreenPresentationStyle)presentationStyle {
  return [self initWithPresentationStyle:presentationStyle animated:YES];
}
- (instancetype)initWithPresentationStyle:(QONScreenPresentationStyle)presentationStyle animated:(BOOL)animated {
  self = [super init];
  if (self) {
    _presentationStyle = presentationStyle;
    _animated = animated;
  }
  
  return self;
}

@end
