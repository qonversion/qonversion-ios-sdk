#import "QNLaunchResult.h"

@interface QNProperties : NSObject

+ (nullable NSString *)keyForProperty:(QNProperty) property;
+ (BOOL)checkValue:(NSString * _Nonnull)value;
+ (BOOL)checkProperty:(NSString * _Nonnull)property;

@end
