#import <CoreGraphics/CoreGraphics.h>

#import "QNUtils.h"
#import "QONErrors.h"
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

+ (BOOL)isPermissionsOutdatedForDefaultState:(BOOL)defaultState cacheDataTimeInterval:(NSTimeInterval)cacheDataTimeInterval cacheLifetime:(QONEntitlementsCacheLifetime)cacheLifetime {
  CGFloat cacheLifetimeInSeconds = defaultState ? 60.0 * 5.0 : [self cacheLifetimeInSeconds:cacheLifetime];
  return [self isCacheOutdated:cacheDataTimeInterval cacheLifetime:cacheLifetimeInSeconds];
}

+ (CGFloat)cacheLifetimeInSeconds:(QONEntitlementsCacheLifetime)cacheLifetime {
  NSUInteger days = 0;
  switch (cacheLifetime) {
    case QONEntitlementsCacheLifetimeWeek:
      days = 7;
      break;
    case QONEntitlementsCacheLifetimeTwoWeeks:
      days = 14;
      break;
    case QONEntitlementsCacheLifetimeMonth:
      days = 30;
      break;
    case QONEntitlementsCacheLifetimeTwoMonths:
      days = 60;
      break;
    case QONEntitlementsCacheLifetimeThreeMonths:
      days = 90;
      break;
    case QONEntitlementsCacheLifetimeSixMonths:
      days = 180;
      break;
    case QONEntitlementsCacheLifetimeYear:
      days = 365;
      break;
    case QONEntitlementsCacheLifetimeUnlimited:
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

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
// Warning muted for linter
+ (NSDate *)calculateExpirationDateForProduct:(QONProduct *)product fromDate:(NSDate *)transactionDate {
  if (product.type == QONProductTypeDirectSubscription || product.type == QONProductTypeTrial) {
    NSInteger days = 0;
    switch (product.duration) {
      case QONProductDurationWeekly:
        days = 7;
        break;
      case QONProductDurationMonthly:
        days = 30;
        break;
      case QONProductDuration3Months:
        days = 90;
        break;
      case QONProductDuration6Months:
        days = 180;
        break;
      case QONProductDurationAnnual:
        days = 365;
        break;
      case QONProductDurationLifetime:
        return nil;
      case QONProductDurationUnknown:
        return nil;
        
      default:
        return nil;
    }
    
    return [NSDate dateWithTimeInterval:days * [self dayInSeconds] sinceDate:transactionDate];
  } else {
    return nil;
  }
}
#pragma GCC diagnostic pop

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

+ (BOOL)isAuthorizationError:(NSError *)error {
  return [[QNUtils authErrorsCodes] containsObject:@(error.code)];
}

+ (BOOL)shouldPurchaseRequestBeRetried:(NSError *)error {
  if (!error) {
    return NO;
  }
  
  return error.code >= kInternalServerErrorFirstCode && error.code <= kInternalServerErrorLastCode;
}

+ (NSArray *)authErrorsCodes {
   return @[@401, @402, @403];
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
