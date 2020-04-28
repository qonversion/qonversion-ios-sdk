#import <Foundation/Foundation.h>

@interface UserInfo : NSObject

+ (nullable NSBundle *)bundle;
+ (nonnull NSDictionary *)overallData;

+ (void)saveInternalUserID:(nonnull NSString *)uid;

+ (nullable NSString *)appStoreReceipt;

@end
