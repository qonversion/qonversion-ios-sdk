#import <Foundation/Foundation.h>

@interface QNUserInfo : NSObject

+ (nullable NSBundle *)bundle;
+ (nonnull NSDictionary *)overallData;

+ (BOOL)isDebug;
+ (void)saveInternalUserID:(nonnull NSString *)uid;

+ (nullable NSString *)appStoreReceipt;

@end
