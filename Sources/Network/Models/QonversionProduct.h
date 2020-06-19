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
 https://qonversion.io/create-products
 */
@property (nonatomic, copy) NSString *qonversionID;

/**
 Apple Store Product ID
 https://qonversion.io/create-products
 */
@property (nonatomic, copy) NSString *storeID;

/**
 Product types
 https://qonversion.io/product-types
 */
@property (nonatomic) QonversionProductType type;

/**
Product durations
https://qonversion.io/product-durations
*/
@property (nonatomic) QonversionProductDuration duration;

@end
