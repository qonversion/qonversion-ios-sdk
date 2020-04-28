#import <Foundation/Foundation.h>

@interface UserInfo : NSObject

+ (nullable NSBundle *)bundle;
+ (NSDictionary *)overallData;

+ (void)saveInternalUserID:(nonnull NSString *)uid;

@end
