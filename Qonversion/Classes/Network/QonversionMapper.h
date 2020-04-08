#import <Foundation/Foundation.h>
#import "Models/QonversionCheckResult.h"


@interface QonversionMapper : NSObject

+ (QonversionCheckResult *)fillCheckResult:(NSDictionary *)dict;

@end
