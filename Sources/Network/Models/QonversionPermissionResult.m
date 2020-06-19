#import <Foundation/Foundation.h>
#import "QonversionLaunchResult+Protected.h"

@implementation QonversionLaunchResult : NSObject

- (void)setTimestamp:(NSUInteger)timestamp {
    _timestamp = timestamp;
}

- (void)setPermissions:(NSDictionary<NSString *, QonversionPermissionResult *> *)permissions {
    _permissions = permissions;
}

- (void)setProducts:(NSDictionary<NSString *, QonversionProductResult *> *)products {
    _products = products;
}

@end
