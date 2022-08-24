#import "QNConstants.h"
#import "QNProperties.h"
#import "QNUtils.h"

@implementation QNProperties

+ (nullable NSString *)keyForProperty:(QNProperty) property {
  NSString *key = nil;
  switch (property) {
    case QNPropertyEmail:
      key = @"_q_email";
      break;
    case QNPropertyName:
      key = @"_q_name";
      break;
    case QNPropertyKochavaDeviceID:
      key = @"_q_kochava_device_id";
      break;
    case QNPropertyAppsFlyerUserID:
      key = @"_q_appsflyer_user_id";
      break;
    case QNPropertyAdjustUserID:
      key = @"_q_adjust_adid";
      break;
    case QNPropertyAdvertisingID:
      key = @"_q_advertising_id";
      break;
    case QNPropertyUserID:
      key = @"_q_custom_user_id";
      break;
    case QNPropertyFirebaseAppInstanceId:
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
  
  NSRange range = [property rangeOfString:keyQNPropertyReg options:NSRegularExpressionSearch];
  return range.location != NSNotFound;
}

@end
