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
        case QPropertyOnesignalUserID:
            key = @"_q_onesignal_id";
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
