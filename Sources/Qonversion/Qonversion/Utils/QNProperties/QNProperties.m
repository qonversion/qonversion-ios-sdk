#import "QNInternalConstants.h"
#import "QNProperties.h"
#import "QNUtils.h"

@implementation QNProperties

+ (nullable NSString *)keyForProperty:(QONProperty) property {
  NSString *key = nil;
  switch (property) {
    case QONPropertyEmail:
      key = @"_q_email";
      break;
    case QONPropertyName:
      key = @"_q_name";
      break;
    case QONPropertyKochavaDeviceID:
      key = @"_q_kochava_device_id";
      break;
    case QONPropertyAppsFlyerUserID:
      key = @"_q_appsflyer_user_id";
      break;
    case QONPropertyAdjustAdID:
      key = @"_q_adjust_adid";
      break;
    case QONPropertyAdvertisingID:
      key = @"_q_advertising_id";
      break;
    case QONPropertyUserID:
      key = @"_q_custom_user_id";
      break;
    case QONPropertyFirebaseAppInstanceId:
      key = @"_q_firebase_instance_id";
      break;
  }
  
  return key;
}

+ (BOOL)checkValue:(NSString *)value {
  return ![QNUtils isEmptyString:value];
}

+ (BOOL)checkProperty:(NSString *)property {
  if ([QNUtils isEmptyString:property]) {
    return NO;
  }
  
  NSRange range = [property rangeOfString:keyQONPropertyReg options:NSRegularExpressionSearch];
  return range.location != NSNotFound;
}

@end
