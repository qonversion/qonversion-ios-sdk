#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UserInfo : NSObject

+ (nullable NSBundle *)bundle;
+ (NSDictionary *)overallData;

+ (void)saveInternalUserID:(nonnull NSString *)uid;

@end

NS_ASSUME_NONNULL_END
