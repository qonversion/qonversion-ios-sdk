#import <Foundation/Foundation.h>

@class QNMapperObject, QNLaunchResult, QNPermission;

@interface QNMapper : NSObject

+ (QNMapperObject * _Nonnull)mapperObjectFrom:(NSDictionary *)dict;

+ (QNLaunchResult * _Nonnull)fillLaunchResult:(NSDictionary * _Nullable)dict;

+ (NSDictionary <NSString *, QNPermission *> * _Nonnull)fillPermissions:(NSDictionary * _Nullable)dict;

+ (NSInteger)mapInteger:(NSObject *)object; 
@end
