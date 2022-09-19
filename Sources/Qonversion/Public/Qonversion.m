#import "Qonversion.h"

#import "QNAPIClient.h"
#import "QNUserPropertiesManager.h"
#import "QNProductCenterManager.h"
#import "QNAttributionManager.h"
#import "QNProductCenterManager.h"
#import "QNUserInfo.h"
#import "QNProperties.h"
#import "QNDevice.h"
#import "QNUtils.h"
#import "QNUserInfoServiceInterface.h"
#import "QNUserInfoService.h"
#import "QNServicesAssembly.h"
#import "QNInternalConstants.h"

#if TARGET_OS_IOS
#import "QONAutomationsFlowCoordinator.h"
#endif

@interface Qonversion()

@property (nonatomic, strong) QNProductCenterManager *productCenterManager;
@property (nonatomic, strong) QNUserPropertiesManager *propertiesManager;
@property (nonatomic, strong) QNAttributionManager *attributionManager;
@property (nonatomic, strong) id<QNUserInfoServiceInterface> userInfoService;

@property (nonatomic, assign) BOOL debugMode;
@property (nonatomic, assign) BOOL disableFinishTransactions;

@end

@implementation Qonversion

// MARK: - Public

+ (void)launchWithKey:(nonnull NSString *)key {
  [self launchWithKey:key completion:^(QNLaunchResult * _Nonnull result, NSError * _Nullable error) {
    
  }];
}

+ (void)disableFinishTransactions {
  [Qonversion sharedInstance].disableFinishTransactions = YES;
  
  if ([Qonversion sharedInstance].productCenterManager) {
    [Qonversion sharedInstance].productCenterManager.disableFinishTransactions = YES;
  }
}

+ (void)launchWithKey:(nonnull NSString *)key completion:(QNLaunchCompletionHandler)completion {
  NSString *userID = [[Qonversion sharedInstance].userInfoService obtainUserID];
  QONVERSION_LOG(@"🚀 Qonversion initialized with userID: %@", userID);
  
  [[QNAPIClient shared] setApiKey:key];
  [[QNAPIClient shared] setUserID:userID];
  [[QNAPIClient shared] setDebug:[Qonversion sharedInstance].debugMode];
  
  [Qonversion sharedInstance].productCenterManager.disableFinishTransactions = [Qonversion sharedInstance].disableFinishTransactions;
  [[Qonversion sharedInstance].productCenterManager launchWithCompletion:completion];
  
  [Qonversion sharedInstance].propertiesManager.productCenterManager = [Qonversion sharedInstance].productCenterManager;
}

+ (void)setPermissionsCacheLifetime:(QNPermissionsCacheLifetime)cacheLifetime {
  [[Qonversion sharedInstance].productCenterManager setEntitlementsCacheLifetime:cacheLifetime];
}

+ (void)identify:(NSString *)userID {
  [[Qonversion sharedInstance].productCenterManager identify:userID];
}

+ (void)logout {
  [[Qonversion sharedInstance].productCenterManager logout];
}

+ (void)setNotificationsToken:(NSData *)token {
  NSString *tokenString = [QNUtils convertHexData:token];
  NSString *oldToken = [QNDevice current].pushNotificationsToken;
  if ([tokenString isEqualToString:oldToken] || tokenString.length == 0) {
    return;
  }
  
  [[QNDevice current] setPushNotificationsToken:tokenString];
  [[QNDevice current] setPushTokenProcessed:NO];
  [[Qonversion sharedInstance].productCenterManager sendPushToken];
}

#if TARGET_OS_IOS
+ (BOOL)handleNotification:(NSDictionary *)userInfo {
  return [[QONAutomationsFlowCoordinator sharedInstance] handlePushNotification:userInfo];
}

+ (NSDictionary *_Nullable)getNotificationCustomPayload:(NSDictionary *)userInfo {
  NSDictionary *customPayload = userInfo[kKeyNotificationsCustomPayload];
  if (![customPayload isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  
  return customPayload;
}
#endif

+ (void)presentCodeRedemptionSheet {
  [[Qonversion sharedInstance].productCenterManager presentCodeRedemptionSheet];
}

+ (void)setDebugMode {
  [Qonversion sharedInstance].debugMode = YES;
}

+ (void)setPurchasesDelegate:(id<QNPurchasesDelegate>)delegate {
  [[Qonversion sharedInstance].productCenterManager setPurchasesDelegate:delegate];
}

+ (void)setPromoPurchasesDelegate:(id<QNPromoPurchasesDelegate>)delegate {
  [[Qonversion sharedInstance].productCenterManager setPromoPurchasesDelegate:delegate];
}

+ (void)addAttributionData:(NSDictionary *)data fromProvider:(QNAttributionProvider)provider {
  [[Qonversion sharedInstance].attributionManager addAttributionData:data fromProvider:provider];
}

+ (void)setProperty:(QNProperty)property value:(NSString *)value {
  NSString *key = [QNProperties keyForProperty:property];
  
  if (key) {
    [self setUserProperty:key value:value];
  }
}

+ (void)setUserProperty:(NSString *)property value:(NSString *)value {
  [[Qonversion sharedInstance].propertiesManager setUserProperty:property value:value];
}

+ (void)setUserID:(NSString *)userID {
  [self setProperty:QNPropertyUserID value:userID];
}

+ (void)checkPermissions:(QNPermissionCompletionHandler)completion {
  [[Qonversion sharedInstance].productCenterManager checkPermissions:completion];
}

+ (void)purchaseProduct:(QNProduct *)product completion:(QNPurchaseCompletionHandler)completion {
  [[Qonversion sharedInstance].productCenterManager purchaseProduct:product completion:completion];
}

+ (void)purchase:(NSString *)productID completion:(QNPurchaseCompletionHandler)completion {
  [[Qonversion sharedInstance].productCenterManager purchase:productID completion:completion];
}

+ (void)restoreWithCompletion:(QNRestoreCompletionHandler)completion {
  [[Qonversion sharedInstance].productCenterManager restoreWithCompletion:completion];
}

+ (void)products:(QNProductsCompletionHandler)completion {
  return [[Qonversion sharedInstance].productCenterManager products:completion];
}

+ (void)checkTrialIntroEligibilityForProductIds:(NSArray<NSString *> *)productIds completion:(QNEligibilityCompletionHandler)completion {
  [[Qonversion sharedInstance].productCenterManager checkTrialIntroEligibilityForProductIds:productIds completion:completion];
}

+ (void)offerings:(QNOfferingsCompletionHandler)completion {
  return [[Qonversion sharedInstance].productCenterManager offerings:completion];
}

+ (void)experiments:(QNExperimentsCompletionHandler)completion {
  [[Qonversion sharedInstance].productCenterManager experiments:completion];
}

+ (void)setAppleSearchAdsAttributionEnabled:(BOOL)enable {
  if (enable) {
    [[Qonversion sharedInstance].attributionManager addAppleSearchAttributionData];
  }
}

+ (void)resetUser {
  QONVERSION_LOG(@"⚠️ resetUser function was used in debug mode only. You can reinstall the app if you need to reset the user ID.");
}

+ (void)userInfo:(QNUserInfoCompletionHandler)completion {
  [[[Qonversion sharedInstance] productCenterManager] userInfo:completion];
}

// MARK: - Private

+ (instancetype)sharedInstance {
  static id shared = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    shared = self.new;
  });
  
  return shared;
}

- (instancetype)init {
  self = super.init;
  if (self) {
    _productCenterManager = [QNProductCenterManager new];
    _propertiesManager = [QNUserPropertiesManager new];
    _attributionManager = [QNAttributionManager new];
    
    QNServicesAssembly *servicesAssembly = [QNServicesAssembly new];
    
    _userInfoService = [servicesAssembly userInfoService];
    
    _debugMode = NO;
  }
  
  return self;
}

+ (void)setAdvertisingID {
  NSString *idfa = [QNDevice current].advertiserID;
  [Qonversion setProperty:QNPropertyAdvertisingID value:idfa];
}

@end
