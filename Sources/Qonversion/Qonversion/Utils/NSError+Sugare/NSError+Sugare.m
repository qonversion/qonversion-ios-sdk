//
//  NSError+Sugare.m
//  Qonversion
//
//  Created by Suren Sarkisyan on 06.06.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

#import "NSError+Sugare.h"
#import "QNInternalConstants.h"

@implementation NSError (Sugare)

- (BOOL)shouldFireFallback {
  if (self.code == NSURLErrorNotConnectedToInternet || (self.code >= kInternalServerErrorFirstCode && self.code <= kInternalServerErrorLastCode)) {
    return YES;
  } else {
    return NO;
  }
}

@end
