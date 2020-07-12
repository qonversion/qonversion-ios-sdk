#import "QConstants.h"
#import "QNProperties.h"
#import "QNUtils.h"

@implementation QNProperties

+ (nullable NSString *)keyForProperty:(QProperty) property {
  NSString *key = NULL;
  switch (property) {
    case QPropertyEmail:
      key = @"_q_email";
      break;
    case QPropertyName:
      key = @"_q_name";
      break;
    case QPropertyPremium:
      key = @"_q_premium";
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
  
  NSRange range = [property rangeOfString:keyQPropertyReg options:NSRegularExpressionSearch];
  return range.location != NSNotFound;
}

@end
