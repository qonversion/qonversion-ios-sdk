//
//  UserInfo.h
//  Qonversion
//
//  Created by Bogdan Novikov on 23/05/2019.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface UserInfo : NSObject

+ (nullable NSBundle *)bundle;
+ (NSDictionary *)overallData;

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
