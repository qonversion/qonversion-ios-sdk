#import "QConstants.h"
#import "QonversionProperties.h"
#import "QUtils.h"

@implementation QonversionProperties

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
        case QPropertyKochavaDeviceID:
            key = @"_q_kochava_device_id";
            break;
        case QNPropertyAppsFlyerUserID:
            key = @"_q_appsflyer_user_id";
            break;
        case QNPropertyAdjustUserID:
            key = @"_q_adjust_adid";
            break;
    }
    
    return key;
}

+ (BOOL)checkValue:(NSString *)value {
    return ![QUtils isEmptyString:value];
}

+ (BOOL)checkProperty:(NSString *)property {
    if ([QUtils isEmptyString:property]) {
        return NO;
    }
    
    NSRange range = [property rangeOfString:keyQPropertyReg options:NSRegularExpressionSearch];
    return range.location != NSNotFound;
}

@end
