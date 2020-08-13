#import <Foundation/Foundation.h>
#import "QNPermission.h"
#import "QNProduct.h"

NS_SWIFT_NAME(Qonversion.LaunchResult)
@interface QNLaunchResult : NSObject <NSCoding>

/**
 Qonversion User Identifier
 */
@property (nonatomic, copy, readonly) NSString *uid;

/**
 Original Server response time
 */
@property (nonatomic, readonly) NSUInteger timestamp;

/**
 User permissions
 */
@property (nonatomic, copy, readonly) NSDictionary<NSString *, QNPermission *> *permissions;

/**
 All products
 */
@property (nonatomic, copy, readonly) NSDictionary<NSString *, QNProduct *> *products;

/**
 User products
 */
@property (nonatomic, copy, readonly) NSDictionary<NSString *, QNProduct *> *userPoducts;


@end
