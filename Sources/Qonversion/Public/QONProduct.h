#import <StoreKit/StoreKit.h>

typedef NS_ENUM(NSInteger, QONProductType) {
  QONProductTypeUnknown = -1,
  /**
   Provides access to content on a recurring basis with a free introductory offer
   */
  QONProductTypeTrial = 0,
  
  /**
   Provides access to content on a recurring basis
   */
  QONProductTypeDirectSubscription = 1,
  
  /*
    Content that users can purchase with a single, non-recurring charge
   */
  QONProductTypeOneTime = 2
} NS_SWIFT_NAME(Qonversion.ProductType);

typedef NS_ENUM(NSInteger, QONProductDuration) {
  QONProductDurationUnknown = -1,
  QONProductDurationWeekly = 0,
  QONProductDurationMonthly = 1,
  QONProductDuration3Months = 2,
  QONProductDuration6Months = 3,
  QONProductDurationAnnual = 4,
  QONProductDurationLifetime = 5
} NS_SWIFT_NAME(Qonversion.ProductDuration);

typedef NS_ENUM(NSInteger, QONTrialDuration) {
  QONTrialDurationNotAvailable = -1,
  QONTrialDurationUnknown = 0,
  QONTrialDurationThreeDays = 1,
  QONTrialDurationWeek = 2,
  QONTrialDurationTwoWeeks = 3,
  QONTrialDurationMonth = 4,
  QONTrialDurationTwoMonths = 5,
  QONTrialDurationThreeMonths = 6,
  QONTrialDurationSixMonths = 7,
  QONTrialDurationYear = 8,
  QONTrialDurationOther = 9
} NS_SWIFT_NAME(Qonversion.TrialDuration);

NS_SWIFT_NAME(Qonversion.Product)
@interface QONProduct : NSObject <NSCoding>

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

@property (nonatomic, copy, nullable) NSString *offeringID;

/**
 Product type
 Trial, Subscription or one-time purchase
 @see [Products types](https://qonversion.io/docs/create-products#product-type)
 */
@property (nonatomic, assign) QONProductType type;

/**
 Product duration
 @see [Products durations](https://qonversion.io/docs/create-products#product-type)
 */
@property (nonatomic, assign) QONProductDuration duration;

/**
 Trial duration
 */
@property (nonatomic, assign) QONTrialDuration trialDuration;

/**
  Associated StoreKit Product
 */
@property (nonatomic, copy, nullable) SKProduct *skProduct;

/**
  Localized price
  For example, 99,99 USD
 */
@property (nonatomic, copy, nonnull) NSString *prettyPrice;

@end
