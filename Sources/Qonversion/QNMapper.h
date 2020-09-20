#import <Foundation/Foundation.h>

@class QNMapperObject, QNLaunchResult, QNPermission;

@interface QNMapper : NSObject

+ (QNMapperObject * _Nonnull)mapperObjectFrom:(NSDictionary * _Nullable)dict;

+ (QNLaunchResult * _Nonnull)fillLaunchResult:(NSDictionary * _Nullable)dict;

+ (NSDictionary <NSString *, QNPermission *> * _Nonnull)fillPermissions:(NSDictionary * _Nullable)dict;

+ (NSInteger)mapInteger:(NSObject * _Nullable)object;

@end
