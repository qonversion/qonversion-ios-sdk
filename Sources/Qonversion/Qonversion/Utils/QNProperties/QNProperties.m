#import "QNInternalConstants.h"
#import "QNProperties.h"
#import "QNUtils.h"

@implementation QNProperties

+ (nullable NSString *)keyForProperty:(QONUserPropertyKey) property {
  NSString *key = nil;
  switch (property) {
    case QONUserPropertyKeyEmail:
      key = @"_q_email";
      break;
    case QONUserPropertyKeyName:
      key = @"_q_name";
      break;
    case QONUserPropertyKeyKochavaDeviceID:
      key = @"_q_kochava_device_id";
      break;
    case QONUserPropertyKeyAppsFlyerUserID:
      key = @"_q_appsflyer_user_id";
      break;
    case QONUserPropertyKeyAdjustAdID:
      key = @"_q_adjust_adid";
      break;
    case QONUserPropertyKeyAdvertisingID:
      key = @"_q_advertising_id";
      break;
    case QONUserPropertyKeyUserID:
      key = @"_q_custom_user_id";
      break;
    case QONUserPropertyKeyFirebaseAppInstanceId:
      key = @"_q_firebase_instance_id";
      break;
    case QONUserPropertyKeyFacebookAttribution:
      key = @"_q_fb_attribution";
      break;
    case QONUserPropertyKeyAppSetId:
      key = @"_q_app_set_id";
      break;
    case QONUserPropertyKeyCustom:
      key = nil;
      break;
  }
  
  return key;
}

+ (QONUserPropertyKey)propertyKeyFromString:(NSString *)key {
  NSDictionary<NSString *, NSNumber *> *propertiesMap = @{
          @"_q_email": @(QONUserPropertyKeyEmail),
          @"_q_name": @(QONUserPropertyKeyName),
          @"_q_kochava_device_id": @(QONUserPropertyKeyKochavaDeviceID),
          @"_q_appsflyer_user_id": @(QONUserPropertyKeyAppsFlyerUserID),
          @"_q_adjust_adid": @(QONUserPropertyKeyAdjustAdID),
          @"_q_advertising_id": @(QONUserPropertyKeyAdvertisingID),
          @"_q_custom_user_id": @(QONUserPropertyKeyUserID),
          @"_q_firebase_instance_id": @(QONUserPropertyKeyFirebaseAppInstanceId),
          @"_q_fb_attribution": @(QONUserPropertyKeyFacebookAttribution),
          @"_q_app_set_id": @(QONUserPropertyKeyAppSetId),
  };

  return propertiesMap[key].integerValue ?: QONUserPropertyKeyCustom;
}

+ (BOOL)checkValue:(NSString *)value {
  return ![QNUtils isEmptyString:value];
}

+ (BOOL)checkProperty:(NSString *)property {
  if ([QNUtils isEmptyString:property]) {
    return NO;
  }
  
  NSRange range = [property rangeOfString:keyQONUserPropertyKeyReg options:NSRegularExpressionSearch];
  return range.location != NSNotFound;
}

@end
