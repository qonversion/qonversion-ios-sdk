#import "QONUserProperty.h"

@interface QNProperties : NSObject

+ (nullable NSString *)keyForProperty:(QONUserPropertyKey) property;
+ (QONUserPropertyKey)propertyKeyFromString:(NSString *) key;
+ (BOOL)checkValue:(NSString * _Nonnull)value;
+ (BOOL)checkProperty:(NSString * _Nonnull)property;

@end
