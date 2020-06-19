#import <Foundation/Foundation.h>
#import "QonversionLaunchResult+Protected.h"

@implementation QonversionLaunchResult : NSObject

- (void)setTimestamp:(NSUInteger)timestamp {
    _timestamp = timestamp;
}

- (void)setPermissions:(NSDictionary<NSString *, QonversionPermission *> *)permissions {
    _permissions = permissions;
}

- (void)setProducts:(NSDictionary<NSString *, QonversionProduct *> *)products {
    _products = products;
}

@end
