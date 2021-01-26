#import <Foundation/Foundation.h>

@class QNMapperObject, QNLaunchResult, QNPermission, QNIntroEligibility;

@interface QNMapper : NSObject

+ (QNMapperObject * _Nonnull)mapperObjectFrom:(NSDictionary * _Nullable)dict;

+ (QNLaunchResult * _Nonnull)fillLaunchResult:(NSDictionary * _Nullable)dict;

+ (NSDictionary<NSString *, QNIntroEligibility *> * _Nonnull)mapProductsEligibility:(NSDictionary * _Nullable)dict;

+ (NSInteger)mapInteger:(NSObject * _Nullable)object orReturn:(NSInteger)defaultValue;

@end
