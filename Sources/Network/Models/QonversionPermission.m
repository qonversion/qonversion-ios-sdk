#import <Foundation/Foundation.h>
#import "QonversionPermission.h"

@implementation QonversionPermission : NSObject

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (self) {
        _permissionID = [coder decodeObjectForKey:NSStringFromSelector(@selector(permissionID))];
        _qonversionProductID = [coder decodeObjectForKey:NSStringFromSelector(@selector(qonversionProductID))];
        _isActive = [coder decodeBoolForKey:NSStringFromSelector(@selector(isActive))];
        _renewState = [coder decodeIntegerForKey:NSStringFromSelector(@selector(renewState))];
        _startedDate = [coder decodeObjectForKey:NSStringFromSelector(@selector(startedDate))];
        _expirationDate = [coder decodeObjectForKey:NSStringFromSelector(@selector(expirationDate))];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_permissionID forKey:NSStringFromSelector(@selector(permissionID))];
    [coder encodeObject:_qonversionProductID forKey:NSStringFromSelector(@selector(qonversionProductID))];
    [coder encodeBool:_isActive forKey:NSStringFromSelector(@selector(isActive))];
    [coder encodeInteger:_renewState forKey:NSStringFromSelector(@selector(renewState))];
    [coder encodeObject:_startedDate forKey:NSStringFromSelector(@selector(startedDate))];
    [coder encodeObject:_expirationDate forKey:NSStringFromSelector(@selector(expirationDate))];
}

- (NSString *)description
{
    NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: ", NSStringFromClass([self class])];
    
    [description appendFormat:@"id=%@,\n", self.permissionID];
    [description appendFormat:@"isActive=%d,\n", self.isActive];
    [description appendFormat:@"qonversionProductID=%d,\n", self.qonversionProductID];
    [description appendFormat:@"renewState=%li,\n", (long) self.renewState];
    [description appendFormat:@"startedDate=%@,\n", self.startedDate];
    [description appendFormat:@"expirationDate=%@,\n", self.expirationDate];
    [description appendString:@">"];
    return description;
}

@end
