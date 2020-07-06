#import "QRequestSerializer.h"
#import "UserInfo.h"
#import "QDevice.h"

@interface QRequestSerializer ()

@property (nonatomic, strong) NSString *userID;
@property (nonatomic, strong) QDevice *device;

@end

@interface SKProduct (PrettyCurrency)
@property (nonatomic, strong) NSString *prettyCurrency;
@end

@implementation SKProduct (PrettyCurrency)

- (NSString *)prettyCurrency {
  NSString *currency = @"";
  
  if (@available(iOS 10.0, *)) {
    currency = self.priceLocale.currencyCode;
  } else {
    NSNumberFormatter *formatter = NSNumberFormatter.new;
    [formatter setNumberStyle:NSNumberFormatterCurrencyISOCodeStyle];
    [formatter setLocale:self.priceLocale];
    currency = [formatter stringFromNumber:self.price];
  }
  
  return currency;
}

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
  NSMutableDictionary *purchaseDict = [[NSMutableDictionary alloc] init];

  purchaseDict[@"product"] = product.productIdentifier;
  purchaseDict[@"currency"] = product.prettyCurrency;
  purchaseDict[@"value"] = product.price.stringValue;
  purchaseDict[@"transaction_id"] = transaction.transactionIdentifier ?: @"";
  purchaseDict[@"original_transaction_id"] = transaction.originalTransaction.transactionIdentifier ?: @"";
  
  if (@available(iOS 11.2, *)) {
    if (product.subscriptionPeriod != nil) {
      purchaseDict[@"period_unit"] = @(product.subscriptionPeriod.unit).stringValue;
      purchaseDict[@"period_number_of_units"] = @(product.subscriptionPeriod.numberOfUnits).stringValue;
    }
    
    if (product.introductoryPrice != nil) {
      NSMutableDictionary *introductoryPriceDict = [[NSMutableDictionary alloc] init];
      
      SKProductDiscount *introductoryPrice = product.introductoryPrice;
      
      introductoryPriceDict[@"value"] = introductoryPrice.price.stringValue;
      introductoryPriceDict[@"number_of_periods"] = @(introductoryPrice.numberOfPeriods).stringValue;
      introductoryPriceDict[@"period_number_of_units"] = @(introductoryPrice.subscriptionPeriod.numberOfUnits).stringValue;
      introductoryPriceDict[@"period_unit"] = @(introductoryPrice.subscriptionPeriod.unit).stringValue;
      introductoryPriceDict[@"payment_mode"] = @(introductoryPrice.paymentMode).stringValue;
      
      purchaseDict[@"introductory_price"] = introductoryPriceDict;
    }
  }
  
  if (@available(iOS 13.0, *)) {
    NSString *countryCode = SKPaymentQueue.defaultQueue.storefront.countryCode ?: @"";
    purchaseDict[@"country"] = countryCode;
  }
  
  NSMutableDictionary *result = [[NSMutableDictionary alloc] initWithDictionary:self.mainData];
  result[@"purchase"] = purchaseDict;
  
  return result;
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
