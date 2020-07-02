#import <Foundation/Foundation.h>
#import "QonversionLaunchResult+Protected.h"

@implementation QonversionLaunchResult : NSObject

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (self) {
        _uid = [coder decodeObjectForKey:NSStringFromSelector(@selector(uid))];
        _timestamp = [coder decodeIntegerForKey:NSStringFromSelector(@selector(timestamp))];
        _permissions = [coder decodeObjectForKey:NSStringFromSelector(@selector(permissions))];
        _products = [coder decodeObjectForKey:NSStringFromSelector(@selector(products))];
        _userPoducts = [coder decodeObjectForKey:NSStringFromSelector(@selector(userPoducts))];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_uid forKey:NSStringFromSelector(@selector(uid))];
    [coder encodeInteger:_timestamp forKey:NSStringFromSelector(@selector(timestamp))];
    [coder encodeObject:_permissions forKey:NSStringFromSelector(@selector(permissions))];
    [coder encodeObject:_products forKey:NSStringFromSelector(@selector(products))];
    [coder encodeObject:_userPoducts forKey:NSStringFromSelector(@selector(userPoducts))];
}

- (void)setUid:(NSString *)uid {
    _uid = uid;
}

- (void)setTimestamp:(NSUInteger)timestamp {
    _timestamp = timestamp;
}

- (void)setPermissions:(NSDictionary<NSString *, QonversionPermission *> *)permissions {
    _permissions = permissions;
}

- (void)setProducts:(NSDictionary<NSString *, QonversionProduct *> *)products {
    _products = products;
}

- (void)setUserPoducts:(NSDictionary<NSString *, QonversionProduct *> *)userPoducts {
    _userPoducts = userPoducts;
}

@end
