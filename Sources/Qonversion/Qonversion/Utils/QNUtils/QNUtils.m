#import <CoreGraphics/CoreGraphics.h>

#import "QNUtils.h"
#import "QNErrors.h"

@implementation QNUtils

+ (BOOL)isEmptyString:(NSString *)string {
  return string == nil || [string isKindOfClass:[NSNull class]] || [string length] == 0;
}

+ (NSString *)convertHexData:(NSData *)tokenData {
    const unsigned char *bytes = (const unsigned char *)tokenData.bytes;
    NSMutableString *hex = [NSMutableString new];
    for (NSInteger i = 0; i < tokenData.length; i++) {
        [hex appendFormat:@"%02x", bytes[i]];
    }
    return [hex copy];
}

+ (BOOL)isCacheOutdated:(NSTimeInterval)cacheDataTimeInterval {
  CGFloat cacheLifetimeInSeconds = [self defaultCacheLifetime];
  return [self isCacheOutdated:cacheDataTimeInterval cacheLifetime:cacheLifetimeInSeconds];
}

+ (BOOL)isCacheOutdated:(NSTimeInterval)cacheDataTimeInterval cacheLifetime:(CGFloat)cacheLifetimeInSeconds  {
  NSDate *currentDate = [NSDate date];
  return (currentDate.timeIntervalSince1970 - cacheDataTimeInterval) > cacheLifetimeInSeconds;
}

+ (BOOL)isPermissionsOutdatedForDefaultState:(BOOL)defaultState cacheDataTimeInterval:(NSTimeInterval)cacheDataTimeInterval cacheLifetime:(QNEntitlementCacheLifetime)cacheLifetime {
  CGFloat cacheLifetimeInSeconds = defaultState ? 60.0 * 5.0 : [self cacheLifetimeInSeconds:cacheLifetime];
  return [self isCacheOutdated:cacheDataTimeInterval cacheLifetime:cacheLifetimeInSeconds];
}

+ (CGFloat)cacheLifetimeInSeconds:(QNEntitlementCacheLifetime)cacheLifetime {
  NSUInteger days = 0;
  switch (cacheLifetime) {
    case QNEntitlementCacheLifetimeWeek:
      days = 7;
      break;
    case QNEntitlementCacheLifetimeTwoWeeks:
      days = 14;
      break;
    case QNEntitlementCacheLifetimeMonth:
      days = 30;
      break;
    case QNEntitlementCacheLifetimeThreeMonth:
      days = 90;
      break;
    case QNEntitlementCacheLifetimeSixMonth:
      days = 180;
      break;
    case QNEntitlementCacheLifetimeYear:
      days = 365;
      break;
    case QNEntitlementCacheLifetimeUnlimited:
      return CGFLOAT_MAX;;
      break;
      
    default:
      break;
  }
  
  return days * 24.0 * 60.0 * 60.0;
}

+ (NSDate *)dateFromTimestamp:(NSNumber *)timestamp {
  NSDate *date;
  
  if (timestamp && [timestamp isKindOfClass:[NSNumber class]]) {
    date = [NSDate dateWithTimeIntervalSince1970:timestamp.floatValue];
  }
  
  return date;
}

+ (CGFloat)defaultCacheLifetime {
  return 60.0 * 60.0 * 24.0;
}

@end
