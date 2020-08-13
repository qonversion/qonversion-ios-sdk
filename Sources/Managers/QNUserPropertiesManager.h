#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface QNUserPropertiesManager : NSObject

- (void)setUserProperty:(NSString *)property value:(NSString *)value;
- (void)setUserID:(NSString *)userID;
@end

NS_ASSUME_NONNULL_END
