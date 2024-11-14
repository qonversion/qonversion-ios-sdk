#import "QNRequestSerializer.h"
#import "QNUserInfo.h"
#import "QNDevice.h"
#import "QONStoreKitSugare.h"
#import "QONProduct.h"
#import "QONExperiment.h"
#import "QONExperimentGroup.h"
#import "QONStoreKit2PurchaseModel.h"
#import "QONPurchaseOptions.h"

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

- (NSDictionary *)purchaseData:(SKProduct *)product
                   transaction:(SKPaymentTransaction *)transaction
                       receipt:(nullable NSString *)receipt
               purchaseOptions:(nullable QONPurchaseOptions *)purchaseOptions {

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
  
  if (@available(iOS 12.2, macOS 10.14.4, watchOS 6.2, visionOS 1.0, tvOS 12.2, *)) {
    NSString *offerId = transaction.payment.paymentDiscount.identifier;
    if (offerId.length > 0) {
      NSMutableDictionary *promoOffer = [[NSMutableDictionary alloc] init];
      SKProductDiscount *purchasedDiscount = nil;
      for (SKProductDiscount *discount in product.discounts) {
        if ([discount.identifier isEqualToString:offerId]) {
          purchasedDiscount = discount;
        }
      }
      
      if (purchasedDiscount) {
        promoOffer[@"id"] = offerId;
        promoOffer[@"value"] = purchasedDiscount.price.stringValue;
        promoOffer[@"number_of_periods"] = @(purchasedDiscount.numberOfPeriods).stringValue;
        promoOffer[@"period_number_of_units"] = @(purchasedDiscount.subscriptionPeriod.numberOfUnits).stringValue;
        promoOffer[@"period_unit"] = @(purchasedDiscount.subscriptionPeriod.unit).stringValue;
        promoOffer[@"payment_mode"] = @(purchasedDiscount.paymentMode).stringValue;

        result[@"promo_offer"] = [promoOffer copy];
      }
    }
  }
  
  if (purchaseOptions.contextKeys.count > 0) {
    purchaseDict[@"context_keys"] = purchaseOptions.contextKeys;
  }
  
  if (@available(iOS 13.0, macos 10.15, tvOS 13.0, *)) {
    NSString *countryCode = SKPaymentQueue.defaultQueue.storefront.countryCode ?: @"";
    purchaseDict[@"country"] = countryCode;
  }
  
  result[@"purchase"] = purchaseDict;
  
  return result;
}

- (NSDictionary *)promotionalOfferInfoForProduct:(QONProduct *)product
                                      identityId:(NSString *)identityId
                                         receipt:(nullable NSString *)receipt {
  NSMutableDictionary *result = [NSMutableDictionary new];
  
  result[@"product"] = product.storeID;
  result[@"app_account_token"] = identityId;
  result[@"app_bundle_id"] = [NSBundle mainBundle].bundleIdentifier;
  
  return [result copy];
}

- (NSDictionary *)purchaseInfo:(QONStoreKit2PurchaseModel *)purchaseModel
                       receipt:(nullable NSString *)receipt {
  NSMutableDictionary *result = [[NSMutableDictionary alloc] initWithDictionary:self.mainData];
  NSMutableDictionary *purchaseDict = [[NSMutableDictionary alloc] init];

  if (receipt) {
    result[@"receipt"] = receipt;
  }
  
  purchaseDict[@"product"] = purchaseModel.productId;
  purchaseDict[@"currency"] = purchaseModel.currency;
  purchaseDict[@"value"] = purchaseModel.price;
  purchaseDict[@"transaction_id"] = purchaseModel.transactionId;
  purchaseDict[@"original_transaction_id"] = purchaseModel.originalTransactionId;
  purchaseDict[@"period_unit"] = purchaseModel.subscriptionPeriodUnit;
  purchaseDict[@"period_number_of_units"] = purchaseModel.subscriptionPeriodNumberOfUnits;
    
  NSMutableDictionary *introOffer = [[NSMutableDictionary alloc] init];
  
  introOffer[@"value"] = purchaseModel.price;
  introOffer[@"number_of_periods"] = purchaseModel.introductoryNumberOfPeriods;
  introOffer[@"period_number_of_units"] = purchaseModel.introductoryPeriodNumberOfUnits;
  introOffer[@"period_unit"] = purchaseModel.introductoryPeriodUnit;
  introOffer[@"payment_mode"] = purchaseModel.introductoryPaymentMode;
  
  result[@"introductory_offer"] = introOffer.count > 0 ? introOffer : nil;
  
  NSMutableDictionary *promoOffer = [[NSMutableDictionary alloc] init];
  promoOffer[@"id"] = purchaseModel.promoOfferId;
  promoOffer[@"value"] = purchaseModel.promoOfferPrice;
  promoOffer[@"number_of_periods"] = purchaseModel.promoOfferNumberOfPeriods;
  promoOffer[@"period_number_of_units"] = purchaseModel.promoOfferPeriodNumberOfUnits;
  promoOffer[@"period_unit"] = purchaseModel.promoOfferPeriodUnit;
  promoOffer[@"payment_mode"] = purchaseModel.promoOfferPaymentMode;

  result[@"promo_offer"] = [promoOffer copy];
  
  purchaseDict[@"country"] = purchaseModel.storefrontCountryCode;
  
  result[@"purchase"] = purchaseDict;
  
  return result;
}

- (NSDictionary *)introTrialEligibilityDataForProducts:(NSArray<QONProduct *> *)products {
  NSMutableDictionary *result = [[self mainData] mutableCopy];
  
  NSMutableArray *productsLocalData = [NSMutableArray new];
  
  for (QONProduct *product in products) {
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

- (NSDictionary *)attributionDataWithDict:(NSDictionary *)data fromProvider:(QONAttributionProvider)provider {
  NSMutableDictionary *deviceData = [self.mainData mutableCopy];
  // remove unused field for attribution request
  deviceData[@"receipt"] = nil;
  
  NSMutableDictionary *body = @{@"d": [deviceData copy]}.mutableCopy;
  NSMutableDictionary *providerData = [NSMutableDictionary new];
  
  switch (provider) {
    case QONAttributionProviderAppsFlyer:
      [providerData setValue:@"appsflyer" forKey:@"provider"];
      break;
    case QONAttributionProviderAdjust:
      [providerData setValue:@"adjust" forKey:@"provider"];
      break;
    case QONAttributionProviderBranch:
      [providerData setValue:@"branch" forKey:@"provider"];
      break;
    case QONAttributionProviderAppleSearchAds:
      [providerData setValue:@"apple_search_ads" forKey:@"provider"];
      break;
    case QONAttributionProviderAppleAdServices:
      [providerData setValue:@"apple_adservices_token" forKey:@"provider"];
      break;
  }
  
  NSString *_uid = nil;
  NSString *af_uid = QNDevice.current.afUserID;
  if (af_uid && provider == QONAttributionProviderAppsFlyer) {
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
