#import "QNRequestSerializer.h"
#import "QNUserInfo.h"
#import "QNDevice.h"
#import "QNStoreKitSugare.h"

@interface QNRequestSerializer ()

@property (nonatomic, strong) NSString *userID;

@end

@implementation QNRequestSerializer

- (NSDictionary *)launchData {
  return self.mainData;
}

- (NSDictionary *)mainData {
  return QNUserInfo.overallData;
}

- (NSDictionary *)purchaseData:(SKProduct *)product transaction:(SKPaymentTransaction *)transaction {
  NSMutableDictionary *result = [[NSMutableDictionary alloc] initWithDictionary:self.mainData];
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
      NSMutableDictionary *introOffer = [[NSMutableDictionary alloc] init];
      
      SKProductDiscount *introductoryPrice = product.introductoryPrice;
      
      introOffer[@"value"] = introductoryPrice.price.stringValue;
      introOffer[@"number_of_periods"] = @(introductoryPrice.numberOfPeriods).stringValue;
      introOffer[@"period_number_of_units"] = @(introductoryPrice.subscriptionPeriod.numberOfUnits).stringValue;
      introOffer[@"period_unit"] = @(introductoryPrice.subscriptionPeriod.unit).stringValue;
      introOffer[@"payment_mode"] = @(introductoryPrice.paymentMode).stringValue;
      
      result[@"introductory_offer"] = introOffer;
    }
  }
  
  if (@available(iOS 13.0, *)) {
    NSString *countryCode = SKPaymentQueue.defaultQueue.storefront.countryCode ?: @"";
    purchaseDict[@"country"] = countryCode;
  }
  
  result[@"purchase"] = purchaseDict;
  return result;
}

- (NSDictionary *)attributionDataWithDict:(NSDictionary *)data fromProvider:(QNAttributionProvider)provider {
  NSMutableDictionary *body = @{@"d": self.mainData}.mutableCopy;
  NSMutableDictionary *providerData = [NSMutableDictionary new];
  
  switch (provider) {
    case QNAttributionProviderAppsFlyer:
      [providerData setValue:@"appsflyer" forKey:@"provider"];
      break;
    case QNAttributionProviderAdjust:
      [providerData setValue:@"adjust" forKey:@"provider"];
      break;
    case QNAttributionProviderBranch:
      [providerData setValue:@"branch" forKey:@"provider"];
      break;
    case QNAttributionProviderApple:
      [providerData setValue:@"apple" forKey:@"provider"];
      break;
  }
  
  NSString *_uid = nil;
  NSString *af_uid = QNDevice.current.afUserID;
  if (af_uid && provider == QNAttributionProviderAppsFlyer) {
    _uid = af_uid;
  }
  
  [providerData setValue:data forKey:@"d"];
  
  if (_uid) {
    [providerData setValue:_uid forKey:@"uid"];
  }
  
  [body setValue:providerData forKey:@"provider_data"];
  
  return body;
}

@end
