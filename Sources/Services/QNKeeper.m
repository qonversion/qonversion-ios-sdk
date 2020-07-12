#import "QNKeeper.h"
#import "QNKeychain.h"

@implementation QNKeeper

+ (nullable NSString *)userID {
  return [QNKeychain stringForKey:@"Qonversion.QNKeeper.userID"];
}

+ (void)setUserID:(NSString *)userID {
  [QNKeychain setString:userID forKey:@"Qonversion.QNKeeper.userID"];
}

@end
