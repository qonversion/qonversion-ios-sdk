#import <Foundation/Foundation.h>
#import "QConstants.h"

@interface QonversionProperties : NSObject

+ (nullable NSString *)keyForProperty:(QProperty) property;
+ (BOOL)checkValue:(NSString * _Nonnull)value;
+ (BOOL)checkProperty:(NSString * _Nonnull)property;

@end
