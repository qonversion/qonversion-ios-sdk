#import "QNLaunchResult+Protected.h"

@implementation QNLaunchResult : NSObject

- (instancetype)init
{
  self = [super init];
  if (self) {
    _uid = @"";
    _timestamp = [[NSDate dateWithTimeIntervalSince1970:0] timeIntervalSinceReferenceDate];
    _permissions = @{};
    _products = @{};
    _userPoducts = @{};
  }
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
  self = [super init];
  if (self) {
    _uid = [coder decodeObjectForKey:NSStringFromSelector(@selector(uid))];
    _timestamp = [coder decodeIntegerForKey:NSStringFromSelector(@selector(timestamp))];
    _permissions = [coder decodeObjectForKey:NSStringFromSelector(@selector(permissions))];
    _products = [coder decodeObjectForKey:NSStringFromSelector(@selector(products))];
    _userPoducts = [coder decodeObjectForKey:NSStringFromSelector(@selector(userPoducts))];
    _offerings = [coder decodeObjectForKey:NSStringFromSelector(@selector(offerings))];
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
  [coder encodeObject:_offerings forKey:NSStringFromSelector(@selector(offerings))];
}

- (void)setUid:(NSString *)uid {
  _uid = uid;
}

- (void)setTimestamp:(NSUInteger)timestamp {
  _timestamp = timestamp;
}

- (void)setPermissions:(NSDictionary<NSString *, QNPermission *> *)permissions {
  _permissions = permissions;
}

- (void)setProducts:(NSDictionary<NSString *, QNProduct *> *)products {
  _products = products;
}

- (void)setUserProducts:(NSDictionary<NSString *, QNProduct *> *)userPoducts {
  _userPoducts = userPoducts;
}

@end
