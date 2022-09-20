#import <CoreGraphics/CoreGraphics.h>

#import "QNUtils.h"
#import "QNErrors.h"
#import "QNInternalConstants.h"

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

+ (BOOL)isCacheOutdated:(NSTimeInterval)cacheDataTimeInterval cacheLifetime:(CGFloat)cacheLifetimeInSeconds  {
  NSDate *currentDate = [NSDate date];
  return (currentDate.timeIntervalSince1970 - cacheDataTimeInterval) > cacheLifetimeInSeconds;
}

+ (BOOL)isPermissionsOutdatedForDefaultState:(BOOL)defaultState cacheDataTimeInterval:(NSTimeInterval)cacheDataTimeInterval cacheLifetime:(QNPermissionsCacheLifetime)cacheLifetime {
  CGFloat cacheLifetimeInSeconds = defaultState ? 60.0 * 5.0 : [self cacheLifetimeInSeconds:cacheLifetime];
  return [self isCacheOutdated:cacheDataTimeInterval cacheLifetime:cacheLifetimeInSeconds];
}

+ (CGFloat)cacheLifetimeInSeconds:(QNPermissionsCacheLifetime)cacheLifetime {
  NSUInteger days = 0;
  switch (cacheLifetime) {
    case QNPermissionsCacheLifetimeWeek:
      days = 7;
      break;
    case QNPermissionsCacheLifetimeTwoWeeks:
      days = 14;
      break;
    case QNPermissionsCacheLifetimeMonth:
      days = 30;
      break;
    case QNPermissionsCacheLifetimeTwoMonth:
      days = 60;
    case QNPermissionsCacheLifetimeThreeMonth:
      days = 90;
      break;
    case QNPermissionsCacheLifetimeSixMonth:
      days = 180;
      break;
    case QNPermissionsCacheLifetimeYear:
      days = 365;
      break;
    case QNPermissionsCacheLifetimeUnlimited:
      return CGFLOAT_MAX;
      break;
      
    default:
      break;
  }
  
  return days * [self dayInSeconds];
}

+ (NSDate *)dateFromTimestamp:(NSNumber *)timestamp {
  NSDate *date;
  
  if (timestamp && [timestamp isKindOfClass:[NSNumber class]]) {
    date = [NSDate dateWithTimeIntervalSince1970:timestamp.floatValue];
  }
  
  return date;
}

+ (NSDate *)calculateExpirationDateForProduct:(QNProduct *)product fromDate:(NSDate *)transactionDate {
  if (product.type == QNProductTypeDirectSubscription || product.type == QNProductTypeTrial) {
    NSInteger days = 0;
    switch (product.duration) {
      case QNProductDurationWeekly:
        days = 7;
        break;
      case QNProductDurationMonthly:
        days = 30;
        break;
      case QNProductDuration3Months:
        days = 90;
        break;
      case QNProductDuration6Months:
        days = 180;
        break;
      case QNProductDurationAnnual:
        days = 365;
        break;
      case QNProductDurationLifetime:
        return nil;
      case QNProductDurationUnknown:
        return nil;
        
      default:
        return nil;
    }
    
    return [NSDate dateWithTimeInterval:days * [self dayInSeconds] sinceDate:transactionDate];
  } else {
    return nil;
  }
}

+ (BOOL)isConnectionError:(NSError *)error {
  NSArray *connectionErrorCodes = @[
    @(NSURLErrorNotConnectedToInternet),
    @(NSURLErrorCallIsActive),
    @(NSURLErrorNetworkConnectionLost),
    @(NSURLErrorDataNotAllowed),
    @(NSURLErrorTimedOut)
  ];
  
  return [connectionErrorCodes containsObject:@(error.code)];
}

+ (BOOL)shouldPurchaseRequestBeRetried:(NSError *)error {
  if (!error) {
    return NO;
  }
  
  return error.code >= kInternalServerErrorFirstCode && error.code <= kInternalServerErrorLastCode;
}

+ (NSDate *)calculateExpirationDateForPeriod:(SKProductSubscriptionPeriod *)period fromDate:(NSDate *)transactionDate {
  if (!period) {
    return nil;
  }
  
  NSDate *startDate = transactionDate ?: [NSDate date];
  NSInteger days = 1;
  switch (period.unit) {
    case SKProductPeriodUnitDay:
      days = 1;
      break;
    case SKProductPeriodUnitWeek:
      days = 7;
      break;
    case SKProductPeriodUnitMonth:
      days = 30;
      break;
    case SKProductPeriodUnitYear:
      days = 365;
      break;
      
    default:
      break;
  }
  
  CGFloat periodInSeconds = days * period.numberOfUnits * [self dayInSeconds];
  
  return [NSDate dateWithTimeInterval:periodInSeconds sinceDate:startDate];
}

+ (CGFloat)dayInSeconds {
  return 60.0 * 60.0 * 24.0;
}

@end
