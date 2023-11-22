#import <Foundation/Foundation.h>

@interface QNUserInfo : NSObject

+ (nullable NSBundle *)bundle;
+ (nonnull NSDictionary *)overallData;

+ (BOOL)isDebug;

+ (nullable NSString *)appStoreReceipt;

@end
