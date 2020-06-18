#import "QRequestSerializer.h"
#import "UserInfo.h"
#import "QDevice.h"

@interface QRequestSerializer ()

@property (nonatomic, strong) NSString *userID;
@property (nonatomic, strong) QDevice *device;

@end

@implementation QRequestSerializer

- (instancetype)initWithUserID:(NSString *)uid {
    if (self = [super init]) {
        _userID = uid;
        _device = [[QDevice alloc] init];
    }
    return self;
}

- (NSDictionary *)launchData {
    return self.mainData;
}

- (NSDictionary *)mainData {
    return UserInfo.overallData;
}

- (NSDictionary *)purchaseData:(SKProduct *)product transaction:(SKPaymentTransaction *)transaction {
    NSString *receipt = UserInfo.appStoreReceipt ?: @"";
    
    NSString *currency = @"";
    if (@available(iOS 10.0, *)) {
        currency = product.priceLocale.currencyCode;
    } else {
        NSNumberFormatter *formatter = NSNumberFormatter.new;
        [formatter setNumberStyle:NSNumberFormatterCurrencyISOCodeStyle];
        [formatter setLocale:product.priceLocale];
        currency = [formatter stringFromNumber:product.price];
    }
    
    NSMutableDictionary *inappDict = @{@"product": product.productIdentifier,
                                       @"receipt": receipt,
                                       @"transactionIdentifier": transaction.transactionIdentifier ?: @"",
                                       @"originalTransactionIdentifier": transaction.originalTransaction.transactionIdentifier ?: @"",
                                       @"currency": currency,
                                       @"value": product.price.stringValue
    }.mutableCopy;
    
    if (@available(iOS 11.2, *)) {
        if (product.subscriptionPeriod != nil) {
            inappDict[@"subscriptionPeriodUnit"] = @(product.subscriptionPeriod.unit).stringValue;
            inappDict[@"subscriptionPeriodNumberOfUnits"] = @(product.subscriptionPeriod.numberOfUnits).stringValue;
        }
        
        if (product.introductoryPrice != nil) {
            SKProductDiscount *introductoryPrice = product.introductoryPrice;
            NSMutableDictionary *introductoryPriceDict = @{
                @"value": introductoryPrice.price.stringValue,
                @"numberOfPeriods": @(introductoryPrice.numberOfPeriods).stringValue,
                @"subscriptionPeriodNumberOfUnits": @(introductoryPrice.subscriptionPeriod.numberOfUnits).stringValue,
                @"subscriptionPeriodUnit": @(introductoryPrice.subscriptionPeriod.unit).stringValue,
                @"paymentMode": @(introductoryPrice.paymentMode).stringValue
            }.mutableCopy;
            
            inappDict[@"introductoryPrice"] = introductoryPriceDict;
        }
        
    }
    
    if (@available(iOS 13.0, *)) {
        NSString *countryCode = SKPaymentQueue.defaultQueue.storefront.countryCode ?: @"";
        
        if (countryCode.length > 0) {
            inappDict[@"country"] = countryCode;
        }
    }
    

    return @{@"inapp": inappDict, @"d": self.mainData};
}

- (NSDictionary *)attributionDataWithDict:(NSDictionary *)data fromProvider:(QAttributionProvider)provider userID:(nullable NSString *)uid {
    NSMutableDictionary *body = @{@"d": self.mainData}.mutableCopy;
    NSMutableDictionary *providerData = [NSMutableDictionary new];
    
    switch (provider) {
        case QAttributionProviderAppsFlyer:
            [providerData setValue:@"appsflyer" forKey:@"provider"];
            break;
        case QAttributionProviderAdjust:
            [providerData setValue:@"adjust" forKey:@"provider"];
            break;
        case QAttributionProviderBranch:
            [providerData setValue:@"branch" forKey:@"provider"];
            break;
    }
    
    NSString *_uid = nil;
    
    if (uid) {
        _uid = uid;
    } else {
        /** Temporary workaround for keep backward compatibility  */
        /** Recommend to remove after moving all clients to version > 1.0.4 */
        NSString *af_uid = _device.afUserID;
        if (af_uid && provider == QAttributionProviderAppsFlyer) {
            _uid = af_uid;
        }
    }
    
    [providerData setValue:data forKey:@"d"];
    
    if (_uid) {
        [providerData setValue:_uid forKey:@"uid"];
    }
    
    [body setValue:providerData forKey:@"provider_data"];
    
}

@end
