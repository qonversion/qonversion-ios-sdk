#import "Keeper.h"
#import "Keychain.h"

@implementation Keeper

+ (nullable NSString *)userID {
  return [Keychain stringForKey:@"Qonversion.Keeper.userID"];
}

+ (void)setUserID:(NSString *)userID {
  [Keychain setString:userID forKey:@"Qonversion.Keeper.userID"];
}

@end
