#import <Foundation/Foundation.h>

typedef NS_ENUM(unsigned int, QonversionProductType){
    QonversionProductTypeUnknown = -1,
    QonversionProductTypeTrial = 0,
    QonversionProductTypeSubscription = 1,
    QonversionProductTypeOneTime = 2
};

typedef NS_ENUM(unsigned int, QonversionProductDuration){
    QonversionProductDurationUnknown = -1,
    QonversionProductDurationWeekly = 0,
    QonversionProductDurationMonthly = 1,
    QonversionProductDuration3Month = 2,
    QonversionProductDuration6Month = 3,
    QonversionProductDurationAnnual = 4,
    QonversionProductDurationLifetime = 5
};

@interface QonversionProduct : NSObject

/**
 Product ID created in Qonversion Dashboard
 @see [Create Products](https://qonversion.io/docs/create-products)
 */
@property (nonatomic, copy) NSString *qonversionID;

/**
 Apple Store Product ID
 @see [Create Products](https://qonversion.io/docs/create-products)
 */
@property (nonatomic, copy) NSString *storeID;

/**
 Product types
 @see [Products types](https://qonversion.io/docs/product-types)
 */
@property (nonatomic) QonversionProductType type;

/**
Product durations
@see [Products durations](https://qonversion.io/docs/product-durations)
*/
@property (nonatomic) QonversionProductDuration duration;

@end
