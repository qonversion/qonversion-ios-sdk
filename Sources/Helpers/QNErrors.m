#import "QNErrors.h"

@implementation QNErrors

+ (NSError *)errorWithCode:(QNErrorCode)errorCode  {
  NSDictionary *info = @{NSLocalizedDescriptionKey: NSLocalizedString(message, nil)};
  return [[NSError alloc] initWithDomain:QNErrorDomain code:errorCode userInfo:info];
}

@end
