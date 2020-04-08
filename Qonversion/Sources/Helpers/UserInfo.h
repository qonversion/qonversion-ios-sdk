#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UserInfo : NSObject

+ (nullable NSBundle *)bundle;
+ (NSDictionary *)overallData;

+ (void)saveInternalUserID:(nonnull NSString *)uid;

@end

@interface NSBundle(Dict)

- (NSString *)name;
- (NSString *)version;
- (NSString *)build;

@end

@interface UIScreen(Size)

- (CGSize)size;

@end

@interface UIDevice(Model)

- (NSString *)model;

@end

NS_ASSUME_NONNULL_END
