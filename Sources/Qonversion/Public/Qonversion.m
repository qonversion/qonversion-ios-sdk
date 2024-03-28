#import "Qonversion.h"

#import "QNAPIClient.h"
#import "QNUserPropertiesManager.h"
#import "QNProductCenterManager.h"
#import "QNAttributionManager.h"
#import "QNProperties.h"
#import "QNDevice.h"
#import "QNUtils.h"
#import "QNUserInfoServiceInterface.h"
#import "QNServicesAssembly.h"
#import "QNLocalStorage.h"
#import "QNInternalConstants.h"
#import "QONRemoteConfigManager.h"
#import "QONExceptionManager.h"
#import "QONUserProperty.h"

static id shared = nil;

@interface Qonversion()

@property (nonatomic, strong) QNProductCenterManager *productCenterManager;
@property (nonatomic, strong) QNUserPropertiesManager *propertiesManager;
@property (nonatomic, strong) QNAttributionManager *attributionManager;
@property (nonatomic, strong) QONRemoteConfigManager *remoteConfigManager;
@property (nonatomic, strong) QONExceptionManager *exceptionManager;
@property (nonatomic, strong) id<QNUserInfoServiceInterface> userInfoService;
@property (nonatomic, strong) id<QNLocalStorage> localStorage;

@property (nonatomic, assign) BOOL debugMode;
@property (nonatomic, assign) QONLaunchMode launchMode;

@end

@implementation Qonversion

static bool _isInitialized = NO;

// MARK: - Public

+ (instancetype)initWithConfig:(QONConfiguration *)configuration {
  if (_isInitialized) {
    return [Qonversion sharedInstance];
  }
  
  _isInitialized = YES;
  
  QONConfiguration *configCopy = [configuration copy];
  
  // Initialization of Qonversion instance
  [Qonversion sharedInstanceWithCustomUserDefaults:configCopy.customUserDefaults];
  
  [Qonversion sharedInstance].debugMode = configCopy.environment == QONEnvironmentSandbox;
  [[QNAPIClient shared] setLocalStorage:[Qonversion sharedInstance].localStorage];
  [[QNAPIClient shared] setSDKVersion:configCopy.version];
  [[QNAPIClient shared] setBaseURL:configCopy.baseURL];
  [Qonversion sharedInstance].launchMode = configCopy.launchMode;
  [[Qonversion sharedInstance].productCenterManager setEntitlementsCacheLifetime:configCopy.entitlementsCacheLifetime];
  [[Qonversion sharedInstance] setEntitlementsUpdateListener:configCopy.entitlementsUpdateListener];
  [[Qonversion sharedInstance] setPromoPurchasesDelegate:configCopy.promoPurchasesDelegate];
  
  [[Qonversion sharedInstance] launchWithKey:configCopy.projectKey completion:^(QONLaunchResult * _Nonnull result, NSError * _Nullable error) {
    
  }];

  return [Qonversion sharedInstance];
}

+ (instancetype)sharedInstanceWithCustomUserDefaults:(NSUserDefaults *)userDefaults {
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    shared = [[self alloc] initWithCustomUserDefaults:userDefaults];
  });
  
  return shared;
}

+ (instancetype)sharedInstance {
  if (!_isInitialized) {
    QONVERSION_ERROR(@"Attempt to get Qonversion instance before initialization. Please, call `initWithConfig` first.");
    return nil;
  }
  
  return shared;
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

- (void)syncHistoricalData {
  BOOL isHistoricalDataSynced = [self.localStorage loadBoolforKey:kHistoricalDataSynced];
  if (isHistoricalDataSynced) {
    return;
  }
  
  [[Qonversion sharedInstance] restore:^(NSDictionary<NSString *,QONEntitlement *> * _Nonnull result, NSError * _Nullable error) {
    if (error) {
      QONVERSION_LOG(@"❌ Historical data sync failed: %@", error.localizedDescription);
    } else {
      [self.localStorage storeBool:YES forKey:kHistoricalDataSynced];
    }
  }];
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

- (void)setEntitlementsUpdateListener:(id<QONEntitlementsUpdateListener>)delegate {
  [[Qonversion sharedInstance].productCenterManager setPurchasesDelegate:delegate];
}

- (void)setPromoPurchasesDelegate:(id<QONPromoPurchasesDelegate>)delegate {
  [[Qonversion sharedInstance].productCenterManager setPromoPurchasesDelegate:delegate];
}

- (void)attribution:(NSDictionary *)data fromProvider:(QONAttributionProvider)provider {
  [[Qonversion sharedInstance].attributionManager addAttributionData:data fromProvider:provider];
}

- (void)setUserProperty:(QONUserPropertyKey)key value:(NSString *)value {
  if (key == QONUserPropertyKeyCustom) {
    QONVERSION_ERROR(@"Can not set user property with the key `Custom`. "
                     "To set custom user property, use the `setCustomUserProperty` method.");
    return;
  }

  NSString *stringKey = [QNProperties keyForProperty:key];
  
  if (stringKey) {
    [self setCustomUserProperty:stringKey value:value];
  }
}

- (void)setCustomUserProperty:(NSString *)property value:(NSString *)value {
  [[Qonversion sharedInstance].propertiesManager setUserProperty:property value:value];
}

- (void)userProperties:(QONUserPropertiesCompletionHandler)completion {
  [[Qonversion sharedInstance].propertiesManager getUserProperties:completion];
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

- (void)remoteConfig:(QONRemoteConfigCompletionHandler)completion {
  [[[Qonversion sharedInstance] remoteConfigManager] obtainRemoteConfigWithContextKey:nil completion:completion];
}

- (void)remoteConfig:(NSString *)contextKey completion:(QONRemoteConfigCompletionHandler)completion {
  [[[Qonversion sharedInstance] remoteConfigManager] obtainRemoteConfigWithContextKey:contextKey completion:completion];
}

- (void)remoteConfigList:(NSArray<NSString *> *)contextKeys includeEmptyContextKey:(BOOL)includeEmptyContextKey completion:(QONRemoteConfigListCompletionHandler)completion {
  [[[Qonversion sharedInstance] remoteConfigManager] obtainRemoteConfigListWithContextKeys:contextKeys includeEmptyContextKey:includeEmptyContextKey completion:completion];
}

- (void)remoteConfigList:(QONRemoteConfigListCompletionHandler)completion {
  [[[Qonversion sharedInstance] remoteConfigManager] obtainRemoteConfigList:completion];
}

- (void)attachUserToExperiment:(NSString *)experimentId groupId:(NSString *)groupId completion:(QONExperimentAttachCompletionHandler)completion {
  [[[Qonversion sharedInstance] remoteConfigManager] attachUserToExperiment:experimentId groupId:groupId completion:completion];
}

- (void)detachUserFromExperiment:(NSString *)experimentId completion:(QONExperimentAttachCompletionHandler)completion {
  [[[Qonversion sharedInstance] remoteConfigManager] detachUserFromExperiment:experimentId completion:completion];
}

- (void)attachUserToRemoteConfiguration:(NSString *)remoteConfigurationId completion:(QONRemoteConfigurationAttachCompletionHandler)completion {
  [[[Qonversion sharedInstance] remoteConfigManager] attachUserToRemoteConfiguration:remoteConfigurationId completion:completion];
}

- (void)detachUserFromRemoteConfiguration:(NSString *)remoteConfigurationId completion:(QONRemoteConfigurationAttachCompletionHandler)completion {
  [[[Qonversion sharedInstance] remoteConfigManager] detachUserFromRemoteConfiguration:remoteConfigurationId completion:completion];
}

- (void)handlePurchases:(NSArray<QONStoreKit2PurchaseModel *> *)purchasesInfo {
  [[Qonversion sharedInstance] handlePurchases:purchasesInfo completion:nil];
}

- (void)handlePurchases:(NSArray<QONStoreKit2PurchaseModel *> *)purchasesInfo completion:(nullable QONDefaultCompletionHandler)completion {
  [[[Qonversion sharedInstance] productCenterManager] handlePurchases:purchasesInfo completion:completion];
}

// MARK: - Private

- (instancetype)initWithCustomUserDefaults:(NSUserDefaults *)userDefaults {
  self = [super init];
  if (self) {
    QNServicesAssembly *servicesAssembly = [[QNServicesAssembly alloc] initWithCustomUserDefaults:userDefaults];
    
    _userInfoService = [servicesAssembly userInfoService];
    _localStorage = [servicesAssembly localStorage];
    id<QNIdentityManagerInterface> identityManager = [servicesAssembly identityManager];
    
    _productCenterManager = [[QNProductCenterManager alloc] initWithUserInfoService:_userInfoService identityManager:identityManager localStorage:_localStorage];
    _propertiesManager = [QNUserPropertiesManager new];
    _attributionManager = [QNAttributionManager new];
    _remoteConfigManager = [QONRemoteConfigManager new];
    _exceptionManager = [QONExceptionManager shared];
    
    _productCenterManager.remoteConfigManager = _remoteConfigManager;
    _remoteConfigManager.productCenterManager = _productCenterManager;
    
    
    _debugMode = NO;
  }
  
  return self;
}

- (void)collectAdvertisingId {
  NSString *idfa = [QNDevice current].advertiserID;
  [[Qonversion sharedInstance] setUserProperty:QONUserPropertyKeyAdvertisingID value:idfa];
}

@end
