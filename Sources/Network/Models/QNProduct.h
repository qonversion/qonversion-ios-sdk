#import <Foundation/Foundation.h>
#import <StoreKit/StoreKit.h>

typedef NS_ENUM(unsigned int, QNProductType){
  QNProductTypeUnknown = -1,
  QNProductTypeTrial = 0,
  QNProductTypeSubscription = 1,
  QNProductTypeOneTime = 2
};

typedef NS_ENUM(unsigned int, QNProductDuration){
  QNProductDurationUnknown = -1,
  QNProductDurationWeekly = 0,
  QNProductDurationMonthly = 1,
  QNProductDuration3Month = 2,
  QNProductDuration6Month = 3,
  QNProductDurationAnnual = 4,
  QNProductDurationLifetime = 5
};

NS_SWIFT_NAME(Qonversion.Product)
@interface QNProduct : NSObject <NSCoding>

/**
 Product ID created in Qonversion Dashboard
 @see [Create Products](https://qonversion.io/docs/create-products)
 */
@property (nonatomic, copy, nonnull) NSString *qonversionID;

/**
 Apple Store Product ID
 @see [Create Products](https://qonversion.io/docs/create-products)
 */
@property (nonatomic, copy, nonnull) NSString *storeID;

/**
 Product type
 Trial, Subscription or one-time purchase
 @see [Products types](https://qonversion.io/docs/product-types)
 */
@property (nonatomic) QNProductType type;

/**
 Product duration
 @see [Products durations](https://qonversion.io/docs/product-durations)
 */
@property (nonatomic) QNProductDuration duration;

/**
  Associated StoreKit Product
 */
@property (nonatomic, copy, readonly, nullable) SKProduct *skProduct;

/**
  Localized price
  For example, 1 490,00 USD
 */
@property (nonatomic, copy, nonnull) NSString *prettyPrice;

@end
