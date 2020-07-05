#import "QUtils.h"

@implementation QUtils

+ (BOOL)isEmptyString:(NSString*)string {
  return string == nil || [string isKindOfClass:[NSNull class]] || [string length] == 0;
}

@end
