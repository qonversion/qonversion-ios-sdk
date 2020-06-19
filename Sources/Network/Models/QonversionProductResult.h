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

@interface QonversionProductResult : NSObject

@property (nonatomic, copy) NSString *qonversionID;
@property (nonatomic, copy) NSString *storeID;

@property (nonatomic) QonversionProductType type;
@property (nonatomic) QonversionProductDuration duration;

@end
