#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface QNKeeper : NSObject

+ (nullable NSString *)userID;
+ (void)setUserID:(NSString *)userID;

@end

NS_ASSUME_NONNULL_END
