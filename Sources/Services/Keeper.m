#import "Keeper.h"
#import "QNKeychain.h"

@implementation Keeper

+ (nullable NSString *)userID {
  return [QNKeychain stringForKey:@"Qonversion.Keeper.userID"];
}

+ (void)setUserID:(NSString *)userID {
  [QNKeychain setString:userID forKey:@"Qonversion.Keeper.userID"];
}

@end
