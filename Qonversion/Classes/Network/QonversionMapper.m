#import <Foundation/Foundation.h>
#import "QonversionMapper.h"
#import "QonversionCheckResult+Protected.h"

@interface QonversionCheckResult()

@end


@implementation QonversionMapper

+ (QonversionCheckResult *)fillCheckResultWith:(NSDictionary *)dict {
  QonversionCheckResult *result = [[QonversionCheckResult alloc] init];
  
  [result setTimestamp:1];
  
  return result;
}

@end
