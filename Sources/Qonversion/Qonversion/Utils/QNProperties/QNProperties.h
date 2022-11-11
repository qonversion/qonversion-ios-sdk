#import "QONLaunchResult.h"

@interface QNProperties : NSObject

+ (nullable NSString *)keyForProperty:(QONProperty) property;
+ (BOOL)checkValue:(NSString * _Nonnull)value;
+ (BOOL)checkProperty:(NSString * _Nonnull)property;

@end
