#import <StoreKit/StoreKit.h>

typedef NS_ENUM(NSInteger, QNProductType) {
  QNProductTypeUnknown = -1,
  /**
   Provides access to content on a recurring basis with a free introductory offer
   */
  QNProductTypeTrial = 0,
  
  /**
   Provides access to content on a recurring basis
   */
  QNProductTypeDirectSubscription = 1,
  
  /*
    Content that users can purchase with a single, non-recurring charge
   */
  QNProductTypeOneTime = 2
} NS_SWIFT_NAME(Qonversion.ProductType);

typedef NS_ENUM(NSInteger, QNProductDuration) {
  QNProductDurationUnknown = -1,
  QNProductDurationWeekly = 0,
  QNProductDurationMonthly = 1,
  QNProductDuration3Months = 2,
  QNProductDuration6Months = 3,
  QNProductDurationAnnual = 4,
  QNProductDurationLifetime = 5
} NS_SWIFT_NAME(Qonversion.ProductDuration);

typedef NS_ENUM(NSInteger, QNTrialDuration) {
  QNTrialDurationNotAvailable = -1,
  QNTrialDurationThreeDays = 1,
  QNTrialDurationWeek = 2,
  QNTrialDurationTwoWeeks = 3,
  QNTrialDurationMonth = 4,
  QNTrialDurationTwoMonths = 5,
  QNTrialDurationThreeMonths = 6,
  QNTrialDurationSixMonths = 7,
  QNTrialDurationYear = 8,
  QNTrialDurationOther = 9
} NS_SWIFT_NAME(Qonversion.TrialDuration);

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

@property (nonatomic, copy, nullable) NSString *offeringID;

/**
 Product type
 Trial, Subscription or one-time purchase
 @see [Products types](https://qonversion.io/docs/create-products#product-type)
 */
@property (nonatomic, assign) QNProductType type;

/**
 Product duration
 @see [Products durations](https://qonversion.io/docs/create-products#product-type)
 */
@property (nonatomic, assign) QNProductDuration duration;

/**
 Trial duration
 */
@property (nonatomic, assign) QNTrialDuration trialDuration;

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
