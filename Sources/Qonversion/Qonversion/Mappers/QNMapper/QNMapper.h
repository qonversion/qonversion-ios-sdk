#import <Foundation/Foundation.h>

@class QNMapperObject, QNLaunchResult, QNPermission, QNIntroEligibility, QNUser;

@interface QNMapper : NSObject

+ (QNMapperObject * _Nonnull)mapperObjectFrom:(NSDictionary * _Nullable)dict;

+ (QNLaunchResult * _Nonnull)fillLaunchResult:(NSDictionary * _Nullable)dict;

+ (QNUser * _Nonnull)fillUser:(NSDictionary * _Nullable)dict;

+ (NSDictionary <NSString *, QNPermission *> * _Nonnull)fillEntitlements:(NSDictionary * _Nullable)data;
+ (NSDictionary <NSString *, QNPermission *> * _Nonnull)fillPermissions:(NSDictionary * _Nullable)data;

+ (NSDictionary<NSString *, QNIntroEligibility *> * _Nonnull)mapProductsEligibility:(NSDictionary * _Nullable)dict;

+ (NSInteger)mapInteger:(NSObject * _Nullable)object orReturn:(NSInteger)defaultValue;

@end
