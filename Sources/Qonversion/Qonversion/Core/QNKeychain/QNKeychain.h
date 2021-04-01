#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface QNKeychain : NSObject

- (void)setString:(NSString *)string forKey:(NSString *)key;
- (nullable NSString *)stringForKey:(NSString *)key;
- (void)deleteValueForKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
