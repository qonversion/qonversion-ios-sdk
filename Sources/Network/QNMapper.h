#import <Foundation/Foundation.h>

@class QNMapperObject, QNLaunchResult;

@interface QNMapper : NSObject

+ (QNMapperObject *)mapperObjectFrom:(NSDictionary *)dict;

- (QNLaunchResult * _Nonnull)fillLaunchResult:(NSDictionary * _Nullable)dict;
- (NSDictionary <NSString *, QNPermission *> * _Nonnull)fillPermissions:(NSDictionary * _Nullable)dict;

@end
