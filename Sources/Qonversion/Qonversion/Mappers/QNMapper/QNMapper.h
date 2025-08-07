#import <Foundation/Foundation.h>

@class QNMapperObject, QONLaunchResult, QONEntitlement, QONIntroEligibility, QONUser, QONFallbackObject, QONOfferings, QONProduct, QONPromotionalOffer, SKProductDiscount;

@interface QNMapper : NSObject

+ (QNMapperObject * _Nonnull)mapperObjectFrom:(NSDictionary * _Nullable)dict;

+ (QONLaunchResult * _Nonnull)fillLaunchResult:(NSDictionary * _Nullable)dict;

+ (QONUser * _Nonnull)fillUser:(NSDictionary * _Nullable)dict;

+ (NSDictionary * _Nullable)mapProductsEntitlementsRelation:(NSDictionary * _Nullable)dict;

+ (NSDictionary<NSString *, QONIntroEligibility *> * _Nonnull)mapProductsEligibility:(NSDictionary * _Nullable)dict;

+ (NSInteger)mapInteger:(NSObject * _Nullable)object orReturn:(NSInteger)defaultValue;

- (QONOfferings * _Nonnull)mapFallbackOfferings:(NSDictionary * _Nullable)data;

- (NSDictionary <NSString *, QONProduct *> * _Nonnull)mapFallbackProducts:(NSDictionary * _Nullable)data;

- (NSDictionary * _Nullable)mapProductsEntitlementsRelations:(NSDictionary * _Nullable)dict;

+ (QONPromotionalOffer * _Nullable)mapPromoOffer:(NSDictionary * _Nullable)rawData productDiscount:(SKProductDiscount * _Nonnull)productDiscount mappingError:(NSError * _Nullable * _Nullable)error API_AVAILABLE(ios(12.2), macos(10.14.4), watchos(6.2), tvos(12.2), visionos(1.0));

@end
