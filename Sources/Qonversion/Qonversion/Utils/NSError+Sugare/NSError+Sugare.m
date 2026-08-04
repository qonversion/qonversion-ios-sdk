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
#import "Qonversion.h"

@implementation NSError (Sugare)

- (BOOL)shouldFireFallback {
  // A locally short-circuited request (rate limiter) is exactly the case the
  // bundled payload exists for: no network attempt was made, so serving the
  // fallback beats surfacing a hard error. Matters since fallbacks are no
  // longer cached — offline repeat calls hit the limiter instead of the old
  // cached-fallback fast path. The rate-limit arm is domain-pinned: code 35
  // collides with unrelated domains (e.g. POSIX EAGAIN).
  BOOL isRateLimited = [self.domain isEqualToString:QonversionErrorDomain] &&
      self.code == QONErrorCodeApiRateLimitExceeded;
  BOOL isTransientURLFailure = [self.domain isEqualToString:NSURLErrorDomain] &&
      (self.code == NSURLErrorNotConnectedToInternet ||
       self.code == NSURLErrorTimedOut ||
       self.code == NSURLErrorNetworkConnectionLost ||
       self.code == NSURLErrorCannotConnectToHost ||
       self.code == NSURLErrorCannotFindHost ||
       self.code == NSURLErrorDNSLookupFailed ||
       self.code == NSURLErrorCallIsActive ||
       self.code == NSURLErrorDataNotAllowed);
  BOOL isServerFailure = [self.domain isEqualToString:QonversionErrorDomain] &&
      self.code >= kInternalServerErrorFirstCode && self.code <= kInternalServerErrorLastCode;
  // QNAPIClient intentionally normalizes empty bodies, invalid JSON, and
  // response-shape failures to the public internal-error code. Those failures
  // say nothing authoritative about the user's assignment, so LKG is safe.
  BOOL isInternalResponseFailure = [self.domain isEqualToString:QonversionErrorDomain] &&
      self.code == QONErrorCodeInternalError;
  if (isTransientURLFailure ||
      isRateLimited ||
      isServerFailure ||
      isInternalResponseFailure) {
    return YES;
  } else {
    return NO;
  }
}

@end
