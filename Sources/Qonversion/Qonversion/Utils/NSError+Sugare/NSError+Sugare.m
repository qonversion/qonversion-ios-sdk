//
//  NSError+Sugare.m
//  Qonversion
//
//  Created by Suren Sarkisyan on 06.06.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

#import "NSError+Sugare.h"
#import "QNInternalConstants.h"
#import "QONErrors.h"

@implementation NSError (Sugare)

- (BOOL)shouldFireFallback {
  // A locally short-circuited request (rate limiter) is exactly the case the
  // bundled payload exists for: no network attempt was made, so serving the
  // fallback beats surfacing a hard error. Matters since fallbacks are no
  // longer cached — offline repeat calls hit the limiter instead of the old
  // cached-fallback fast path.
  if (self.code == NSURLErrorNotConnectedToInternet ||
      self.code == QONErrorCodeApiRateLimitExceeded ||
      (self.code >= kInternalServerErrorFirstCode && self.code <= kInternalServerErrorLastCode)) {
    return YES;
  } else {
    return NO;
  }
}

@end
