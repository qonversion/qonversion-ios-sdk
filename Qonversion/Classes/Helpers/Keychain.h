//
//  Keychain.h
//  Qonversion
//
//  Created by Bogdan Novikov on 22/05/2019.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Keychain : NSObject

+ (void)setString:(NSString *)string forKey:(NSString *)key;
+ (nullable NSString *)stringForKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
