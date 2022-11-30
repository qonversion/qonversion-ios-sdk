#import <Foundation/Foundation.h>

@class QNMapperObject, QONLaunchResult, QONEntitlement, QONIntroEligibility, QONUser;

@interface QNMapper : NSObject

+ (QNMapperObject * _Nonnull)mapperObjectFrom:(NSDictionary * _Nullable)dict;

+ (QONLaunchResult * _Nonnull)fillLaunchResult:(NSDictionary * _Nullable)dict;

+ (QONUser * _Nonnull)fillUser:(NSDictionary * _Nullable)dict;

+ (NSDictionary * _Nullable)mapProductsEntitlementsRelation:(NSDictionary * _Nullable)dict;

+ (NSDictionary<NSString *, QONIntroEligibility *> * _Nonnull)mapProductsEligibility:(NSDictionary * _Nullable)dict;

+ (NSInteger)mapInteger:(NSObject * _Nullable)object orReturn:(NSInteger)defaultValue;

@end
