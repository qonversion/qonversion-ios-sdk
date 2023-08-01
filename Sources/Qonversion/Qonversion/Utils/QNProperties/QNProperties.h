#import "QONLaunchResult.h"

@interface QNProperties : NSObject

+ (nullable NSString *)keyForProperty:(QONUserPropertyKey) property;
+ (QONUserPropertyKey)propertyForKey:(NSString * _Nonnull) key;
+ (BOOL)checkValue:(NSString * _Nonnull)value;
+ (BOOL)checkProperty:(NSString * _Nonnull)property;

@end
