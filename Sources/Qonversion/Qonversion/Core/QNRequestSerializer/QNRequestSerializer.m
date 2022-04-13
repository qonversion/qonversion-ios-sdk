#import "QNRequestSerializer.h"
#import "QNUserInfo.h"
#import "QNDevice.h"
#import "QNStoreKitSugare.h"
#import "QNProduct.h"
#import "QNProductPurchaseModel.h"
#import "QNExperimentInfo.h"
#import "QNExperimentGroup.h"

@interface QNRequestSerializer ()

@property (nonatomic, strong) NSString *userID;

@end

NS_ASSUME_NONNULL_BEGIN

@implementation QNRequestSerializer

- (NSDictionary *)launchData {
  return self.mainData;
}

- (NSDictionary *)mainData {
  return QNUserInfo.overallData;
}

- (NSDictionary *)pushTokenData {
  NSMutableDictionary *data = [NSMutableDictionary new];
  data[@"push_token"] = [[QNDevice current] pushNotificationsToken];
  data[@"device_id"] = [[QNDevice current] vendorID];
       
  return [data copy];
}

- (NSDictionary *)purchaseData:(SKProduct *)product
                   transaction:(SKPaymentTransaction *)transaction
                       receipt:(nullable NSString *)receipt
                 purchaseModel:(nullable QNProductPurchaseModel *)purchaseModel {

  NSMutableDictionary *result = [[NSMutableDictionary alloc] initWithDictionary:self.mainData];
  NSMutableDictionary *purchaseDict = [[NSMutableDictionary alloc] init];

  if (receipt) {
    result[@"receipt"] = receipt;
  }
  
  purchaseDict[@"product"] = product.productIdentifier;
  purchaseDict[@"currency"] = product.prettyCurrency;
  purchaseDict[@"value"] = product.price.stringValue;
  purchaseDict[@"transaction_id"] = transaction.transactionIdentifier ?: @"";
  purchaseDict[@"original_transaction_id"] = transaction.originalTransaction.transactionIdentifier ?: @"";
  
  if (@available(iOS 11.2, macOS 10.13.2, tvOS 11.2, *)) {
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
  
  if (@available(iOS 13.0, macos 10.15, tvOS 13.0, *)) {
    NSString *countryCode = SKPaymentQueue.defaultQueue.storefront.countryCode ?: @"";
    purchaseDict[@"country"] = countryCode;
  }
  
  if (purchaseModel) {
    purchaseDict[@"product_id"] = purchaseModel.product.qonversionID;
    purchaseDict[@"experiment"] = [self configureExperimentInfo:purchaseModel.experimentInfo];
  }
  
  result[@"purchase"] = purchaseDict;
  
  return result;
}

- (NSDictionary *)configureExperimentInfo:(QNExperimentInfo * _Nullable)experimentInfo {
  NSMutableDictionary *dict = [NSMutableDictionary new];
  
  if (experimentInfo) {
    dict[@"uid"] = experimentInfo.identifier;
  }
  
  return [dict copy];
}

- (NSDictionary *)introTrialEligibilityDataForProducts:(NSArray<QNProduct *> *)products {
  NSMutableDictionary *result = [[self mainData] mutableCopy];
  
  NSMutableArray *productsLocalData = [NSMutableArray new];
  
  for (QNProduct *product in products) {
    NSMutableDictionary *param = [NSMutableDictionary new];
    param[@"store_id"] = product.storeID;
    
    if (@available(iOS 12.0, macOS 10.14, watchOS 6.2, tvOS 12.0, *)) {
      param[@"subscription_group_identifier"] = product.skProduct.subscriptionGroupIdentifier;
    }
    
    [productsLocalData addObject:param];
  }
  
  result[@"products_local_data"] = productsLocalData;
  
  return [result copy];
}

- (NSDictionary *)attributionDataWithDict:(NSDictionary *)data fromProvider:(QNAttributionProvider)provider {
  NSMutableDictionary *deviceData = [self.mainData mutableCopy];
  // remove unused field for attribution request
  deviceData[@"receipt"] = nil;
  
  NSMutableDictionary *body = @{@"d": [deviceData copy]}.mutableCopy;
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
    case QNAttributionProviderAppleSearchAds:
      [providerData setValue:@"apple_search_ads" forKey:@"provider"];
      break;
    case QNAttributionProviderAppleAdServices:
      [providerData setValue:@"apple_adservices_token" forKey:@"provider"];
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

NS_ASSUME_NONNULL_END
