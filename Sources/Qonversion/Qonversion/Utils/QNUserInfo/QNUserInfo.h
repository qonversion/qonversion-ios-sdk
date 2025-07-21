#import <Foundation/Foundation.h>

@interface QNUserInfo : NSObject

+ (NSDictionary *)overallData;
+ (NSString *)appStoreReceipt;
+ (NSBundle *)bundle;
+ (BOOL)isDebug;

#if TARGET_OS_WATCH
+ (NSString *)getWatchAppStoreReceipt;
#endif

@end
