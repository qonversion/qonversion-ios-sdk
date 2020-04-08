#import <Foundation/Foundation.h>
#import "Models/QonversionCheckResult.h"


@interface QonversionMapper : NSObject

+ (QonversionCheckResult *)fillCheckResultWith:(NSDictionary *)dict;

@end
