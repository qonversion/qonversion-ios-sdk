#import <Foundation/Foundation.h>
#import "QonversionPermissionResult.h"
#import "QonversionProductResult.h"

@interface QonversionLaunchResult : NSObject

/**
 Original Server response time
 */
@property (nonatomic, readonly) NSUInteger timestamp;

/**
 User permissions
 */
@property (nonatomic, copy, readonly) NSDictionary<NSString *, QonversionPermissionResult *> *permissions;

/**
 All products
 */
@property (nonatomic, copy, readonly) NSDictionary<NSString *, QonversionProductResult *> *products;

@end
