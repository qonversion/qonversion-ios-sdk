//
//  QONRemoteConfigV2Configuration.m
//  Qonversion
//
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

#import "QONRemoteConfigV2Configuration.h"
#import "QONRemoteConfigV2Configuration+Protected.h"
#import "QNAPIConstants.h"

/** Same budget the gateway states for an environment uid. */
static NSUInteger const kQONRemoteConfigV2EnvironmentUidMaximumCodePoints = 36;

/**
 Unicode code points, counted the way the gateway contract counts them: a
 surrogate pair is one code point, not two units and not a byte count.
 */
static NSUInteger QONRemoteConfigV2CodePointCount(NSString *value) {
  NSUInteger count = 0;
  NSUInteger length = value.length;
  for (NSUInteger index = 0; index < length; index++) {
    unichar unit = [value characterAtIndex:index];
    // A trailing surrogate belongs to the code point its lead already counted.
    // An unpaired one still counts as a code point of its own, which is exactly
    // what an unpaired lead does here too.
    if (unit >= 0xDC00 && unit <= 0xDFFF) continue;
    count += 1;
  }
  return count;
}

@interface QONRemoteConfigV2Configuration ()

+ (void)validateBaseURL:(NSString *)baseURL;
+ (void)validateEnvironmentUid:(NSString *)environmentUid;

@end

@implementation QONRemoteConfigV2Configuration

- (instancetype)initWithEnvironmentUid:(NSString *)environmentUid {
  return [self initWithBaseURL:kRemoteConfigV2APIBase environmentUid:environmentUid];
}

- (instancetype)initWithBaseURL:(NSString *)baseURL
                 environmentUid:(NSString *)environmentUid {
  [QONRemoteConfigV2Configuration validateBaseURL:baseURL];
  [QONRemoteConfigV2Configuration validateEnvironmentUid:environmentUid];

  self = [super init];

  if (self) {
    _baseURL = [baseURL copy];
    _environmentUid = [environmentUid copy];
    _minimumFetchIntervalMilliseconds = 0;
  }

  return self;
}

- (void)setMinimumFetchIntervalMilliseconds:(int64_t)minimumFetchIntervalMilliseconds {
  if (minimumFetchIntervalMilliseconds < 0) {
    [NSException raise:NSInvalidArgumentException
                format:@"Remote Config v2 minimum fetch interval must not be negative, got: %lld",
                       minimumFetchIntervalMilliseconds];
  }

  _minimumFetchIntervalMilliseconds = minimumFetchIntervalMilliseconds;
}

- (NSNumber *)effectiveMinimumFetchIntervalMillisecondsForBuildMode:
    (QONRemoteConfigV2ReadGuardBuildMode)buildMode {
  if (self.minimumFetchIntervalMilliseconds > 0) {
    return @(self.minimumFetchIntervalMilliseconds);
  }

  return buildMode == QONRemoteConfigV2ReadGuardBuildModeDebug ? @0 : nil;
}

- (id)copyWithZone:(NSZone *)zone {
  QONRemoteConfigV2Configuration *copyConfig =
      [[QONRemoteConfigV2Configuration allocWithZone:zone] initWithBaseURL:_baseURL
                                                           environmentUid:_environmentUid];
  [copyConfig setMinimumFetchIntervalMilliseconds:_minimumFetchIntervalMilliseconds];

  return copyConfig;
}

#pragma mark - Validation

+ (void)validateBaseURL:(NSString *)baseURL {
  BOOL absolute = [baseURL isKindOfClass:NSString.class] &&
      ([baseURL hasPrefix:@"http://"] || [baseURL hasPrefix:@"https://"]);
  // The scheme prefix alone is what the contract states, but the SDK has to turn
  // this string into an NSURL to reach the gateway at all. A scheme with no host
  // is refused here, where it reads as a misconfiguration, rather than later,
  // where it would look like a surface that simply never came online.
  NSURL *url = absolute ? [NSURL URLWithString:baseURL] : nil;

  if (!absolute || url.host.length == 0) {
    [NSException raise:NSInvalidArgumentException
                format:@"Remote Config v2 base url must be an absolute http(s) url, got: %@",
                       baseURL];
  }
}

+ (void)validateEnvironmentUid:(NSString *)environmentUid {
  NSUInteger codePoints = [environmentUid isKindOfClass:NSString.class]
      ? QONRemoteConfigV2CodePointCount(environmentUid)
      : 0;

  if (codePoints == 0 || codePoints > kQONRemoteConfigV2EnvironmentUidMaximumCodePoints) {
    [NSException raise:NSInvalidArgumentException
                format:@"Remote Config v2 environment uid must be 1..%lu code points",
                       (unsigned long)kQONRemoteConfigV2EnvironmentUidMaximumCodePoints];
  }
}

@end
