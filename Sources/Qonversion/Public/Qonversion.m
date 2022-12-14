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

@interface Qonversion()

@property (nonatomic, strong) QNProductCenterManager *productCenterManager;
@property (nonatomic, strong) QNUserPropertiesManager *propertiesManager;
@property (nonatomic, strong) QNAttributionManager *attributionManager;
@property (nonatomic, strong) id<QNUserInfoServiceInterface> userInfoService;

@property (nonatomic, assign) BOOL debugMode;
@property (nonatomic, assign) QONLaunchMode launchMode;

@end

@implementation Qonversion

// MARK: - Public

+ (instancetype)initWithConfig:(QONConfiguration *)configuration {
  QONConfiguration *configCopy = [configuration copy];
  [Qonversion sharedInstance].debugMode = configCopy.environment == QONEnvironmentSandbox;
  [[QNAPIClient shared] setSDKVersion:configCopy.version];
  [Qonversion sharedInstance].launchMode = configCopy.launchMode;
  [[Qonversion sharedInstance].productCenterManager setEntitlementsCacheLifetime:configCopy.entitlementsCacheLifetime];
  [[Qonversion sharedInstance] setEntitlementsUpdateListener:configCopy.entitlementsUpdateListener];
  [[Qonversion sharedInstance] setPromoPurchasesDelegate:configCopy.promoPurchasesDelegate];
  
  [[Qonversion sharedInstance] launchWithKey:configCopy.projectKey completion:^(QONLaunchResult * _Nonnull result, NSError * _Nullable error) {
    
  }];
  
  return [Qonversion sharedInstance];
}

- (void)launchWithKey:(nonnull NSString *)key completion:(QONLaunchCompletionHandler)completion {
  NSString *userID = [[Qonversion sharedInstance].userInfoService obtainUserID];
  QONVERSION_LOG(@"🚀 Qonversion initialized with userID: %@", userID);
  
  [[QNAPIClient shared] setApiKey:key];
  [[QNAPIClient shared] setUserID:userID];
  [[QNAPIClient shared] setDebug:[Qonversion sharedInstance].debugMode];
  
  [Qonversion sharedInstance].productCenterManager.launchMode = [Qonversion sharedInstance].launchMode;
  [[Qonversion sharedInstance].productCenterManager launchWithCompletion:completion];
  
  [Qonversion sharedInstance].propertiesManager.productCenterManager = [Qonversion sharedInstance].productCenterManager;
}

- (void)identify:(NSString *)userID {
  [[Qonversion sharedInstance].productCenterManager identify:userID];
}

- (void)logout {
  [[Qonversion sharedInstance].productCenterManager logout];
}

- (void)presentCodeRedemptionSheet {
  [[Qonversion sharedInstance].productCenterManager presentCodeRedemptionSheet];
}

- (void)setDebugMode {
  [Qonversion sharedInstance].debugMode = YES;
}

- (void)setEntitlementsUpdateListener:(id<QONEntitlementsUpdateListener>)delegate {
  [[Qonversion sharedInstance].productCenterManager setPurchasesDelegate:delegate];
}

- (void)setPromoPurchasesDelegate:(id<QONPromoPurchasesDelegate>)delegate {
  [[Qonversion sharedInstance].productCenterManager setPromoPurchasesDelegate:delegate];
}

- (void)attribution:(NSDictionary *)data fromProvider:(QONAttributionProvider)provider {
  [[Qonversion sharedInstance].attributionManager addAttributionData:data fromProvider:provider];
}

- (void)setProperty:(QONProperty)property value:(NSString *)value {
  NSString *key = [QNProperties keyForProperty:property];
  
  if (key) {
    [self setUserProperty:key value:value];
  }
}

- (void)setUserProperty:(NSString *)property value:(NSString *)value {
  [[Qonversion sharedInstance].propertiesManager setUserProperty:property value:value];
}

- (void)checkEntitlements:(QONEntitlementsCompletionHandler)completion {
  [[Qonversion sharedInstance].productCenterManager checkEntitlements:completion];
}

- (void)purchaseProduct:(QONProduct *)product completion:(QONPurchaseCompletionHandler)completion {
  [[Qonversion sharedInstance].productCenterManager purchaseProduct:product completion:completion];
}

- (void)purchase:(NSString *)productID completion:(QONPurchaseCompletionHandler)completion {
  [[Qonversion sharedInstance].productCenterManager purchase:productID completion:completion];
}

- (void)restore:(QNRestoreCompletionHandler)completion {
  [[Qonversion sharedInstance].productCenterManager restore:completion];
}

- (void)products:(QONProductsCompletionHandler)completion {
  return [[Qonversion sharedInstance].productCenterManager products:completion];
}

- (void)checkTrialIntroEligibility:(NSArray<NSString *> *)productIds completion:(QONEligibilityCompletionHandler)completion {
  [[Qonversion sharedInstance].productCenterManager checkTrialIntroEligibilityForProductIds:productIds completion:completion];
}

- (void)offerings:(QONOfferingsCompletionHandler)completion {
  return [[Qonversion sharedInstance].productCenterManager offerings:completion];
}

- (void)collectAppleSearchAdsAttribution {
  [[Qonversion sharedInstance].attributionManager addAppleSearchAttributionData];
}

- (void)userInfo:(QONUserInfoCompletionHandler)completion {
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

- (void)collectAdvertisingId {
  NSString *idfa = [QNDevice current].advertiserID;
  [[Qonversion sharedInstance] setProperty:QONPropertyAdvertisingID value:idfa];
}

@end
