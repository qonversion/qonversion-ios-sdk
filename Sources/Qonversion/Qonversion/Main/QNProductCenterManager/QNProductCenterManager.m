#import "QNProductCenterManager.h"
#import "QNUserDefaultsStorage.h"
#import "QNStoreKitService.h"
#import "QNAPIClient.h"
#import "QNMapper.h"
#import "QONLaunchResult.h"
#import "QNMapperObject.h"
#import "QONProduct.h"
#import "QONErrors.h"
#import "QONEntitlementsUpdateListener.h"
#import "QONPromoPurchasesDelegate.h"
#import "QONOfferings.h"
#import "QONOffering.h"
#import "QONIntroEligibility.h"
#import "QNServicesAssembly.h"
#import "QNIdentityManagerInterface.h"
#import "QNUserInfoServiceInterface.h"
#import "QNProductPurchaseModel.h"
#import "QONExperimentInfo.h"
#import "QNDevice.h"
#import "QNInternalConstants.h"

static NSString * const kLaunchResult = @"qonversion.launch.result";
static NSString * const kLaunchResultTimeStamp = @"qonversion.launch.result.timestamp";
static NSString * const kUserDefaultsSuiteName = @"qonversion.product-center.suite";

@interface QNProductCenterManager() <QNStoreKitServiceDelegate>

@property (nonatomic, weak) id<QONEntitlementsUpdateListener> purchasesDelegate;
@property (nonatomic, weak) id<QONPromoPurchasesDelegate> promoPurchasesDelegate;

@property (nonatomic, strong) QNStoreKitService *storeKitService;
@property (nonatomic, strong) QNUserDefaultsStorage *persistentStorage;
@property (nonatomic, strong) id<QNIdentityManagerInterface> identityManager;
@property (nonatomic, strong) id<QNUserInfoServiceInterface> userInfoService;

@property (nonatomic, copy) QNRestoreCompletionHandler restorePurchasesBlock;
@property (nonatomic, copy) NSArray<SKPaymentTransaction *> *restoredTransactions;

@property (nonatomic, strong) NSMutableDictionary <NSString *, QNPurchaseCompletionHandler> *purchasingBlocks;
@property (nonatomic, strong) NSMutableDictionary <NSString *, QNProductPurchaseModel *> *purchaseModels;
@property (nonatomic, strong) NSMutableArray<QNEntitlementsCompletionHandler> *entitlementsBlocks;
@property (nonatomic, strong) NSMutableArray<QNProductsCompletionHandler> *productsBlocks;
@property (nonatomic, strong) NSMutableArray<QNOfferingsCompletionHandler> *offeringsBlocks;
@property (nonatomic, strong) NSMutableArray<QNExperimentsCompletionHandler> *experimentsBlocks;
@property (nonatomic, strong) NSMutableArray<QNUserInfoCompletionHandler> *userInfoBlocks;
@property (nonatomic, assign) QONEntitlementsCacheLifetime cacheLifetime;
@property (nonatomic, copy) NSDictionary<NSString *, NSArray *> *productsPermissionsRelation;
@property (nonatomic, copy) NSDictionary<NSString *, QONEntitlement *> *entitlements;
@property (nonatomic, strong) QNAPIClient *apiClient;

@property (nonatomic, strong) QONLaunchResult *launchResult;
@property (nonatomic, strong) NSError *launchError;
@property (nonatomic, strong) QONUser *user;

@property (nonatomic, assign) BOOL launchingFinished;
@property (nonatomic, assign) BOOL productsLoading;
@property (nonatomic, assign) BOOL identityInProgress;
@property (nonatomic, assign) BOOL unhandledLogoutAvailable;
@property (nonatomic, copy) NSString *pendingIdentityUserID;

@end

@implementation QNProductCenterManager

- (instancetype)init {
  self = super.init;
  if (self) {
    _launchingFinished = NO;
    _productsLoading = NO;
    _launchError = nil;
    _launchResult = nil;
    _cacheLifetime = QONEntitlementsCacheLifetimeMonth;
    
    QNServicesAssembly *servicesAssembly = [QNServicesAssembly new];
    
    _userInfoService = [servicesAssembly userInfoService];
    _identityManager = [servicesAssembly identityManager];
    
    _apiClient = [QNAPIClient shared];
    _storeKitService = [[QNStoreKitService alloc] initWithDelegate:self];
    
    _persistentStorage = [[QNUserDefaultsStorage alloc] init];
    [_persistentStorage setUserDefaults:[[NSUserDefaults alloc] initWithSuiteName:kUserDefaultsSuiteName]];
    
    _productsPermissionsRelation = [_persistentStorage loadObjectForKey:kKeyQUserDefaultsProductsPermissionsRelation];
    
    _purchaseModels = [NSMutableDictionary new];
    _purchasingBlocks = [NSMutableDictionary new];
    _entitlementsBlocks = [NSMutableArray new];
    _productsBlocks = [NSMutableArray new];
    _offeringsBlocks = [NSMutableArray new];
    _experimentsBlocks = [NSMutableArray new];
    _userInfoBlocks = [NSMutableArray new];
  }
  
  return self;
}

- (void)offeringByIDWasCalled:(NSNotification *)notification {
  QONOffering *offering = notification.object;
  BOOL isOfferingClass = [offering isMemberOfClass:[QONOffering class]];
  if (isOfferingClass) {
    offering.experimentInfo.attached = YES;
    [self.apiClient sendOfferingEvent:offering];
  }
}

- (void)setEntitlementsCacheLifetime:(QONEntitlementsCacheLifetime)cacheLifetime {
  self.cacheLifetime = cacheLifetime;
}

- (void)storeLaunchResultIfNeeded:(QONLaunchResult *)launchResult {
  if (launchResult.timestamp > 0) {
    NSDate *currentDate = [NSDate date];
    [self storePermissions:launchResult.entitlements];
    [self.persistentStorage storeDouble:currentDate.timeIntervalSince1970 forKey:kLaunchResultTimeStamp];
    [self.persistentStorage storeObject:launchResult forKey:kLaunchResult];
  }
}

- (QONLaunchResult * _Nullable)cachedLaunchResult {
  QONLaunchResult *result = [self.persistentStorage loadObjectForKey:kLaunchResult];
  
  return result;
}

- (NSTimeInterval)cachedLaunchResultTimeStamp {
  return [self.persistentStorage loadDoubleForKey:kLaunchResultTimeStamp];
}

- (NSDictionary<NSString *, QONProduct *> *)getActualProducts {
  NSDictionary *products = _launchResult.products ?: @{};
  
  if (self.launchError) {
    QONLaunchResult *cachedResult = [self cachedLaunchResult];
    products = cachedResult ? cachedResult.products : products;
  }
  
  return products;
}

- (QONOfferings * _Nullable)getActualOfferings {
  QONOfferings *offerings = self.launchResult.offerings ?: nil;
  
  if (self.launchError) {
    QONLaunchResult *cachedResult = [self cachedLaunchResult];
    offerings = cachedResult ? cachedResult.offerings : offerings;
  }
  
  return offerings;
}

- (void)sendPushToken {
  if (!_launchingFinished) {
    return;
  }

  [self processPushTokenRequest];
}

- (void)processPushTokenRequest {
  NSString *pushToken = [[QNDevice current] pushNotificationsToken];
  BOOL isPushTokenProcessed = [[QNDevice current] isPushTokenProcessed];
  if (!pushToken || isPushTokenProcessed) {
    return;
  }
  
  [self.apiClient sendPushToken:^(BOOL success) {
    if (success) {
      [[QNDevice current] setPushTokenProcessed:YES];
    }
  }];
}

- (void)launchWithCompletion:(nullable QNLaunchCompletionHandler)completion {
  _launchingFinished = NO;
  
  __block __weak QNProductCenterManager *weakSelf = self;
  
  [self launch:^(QONLaunchResult * _Nonnull result, NSError * _Nullable error) {
    [weakSelf processPushTokenRequest];
    [weakSelf storeLaunchResultIfNeeded:result];
    
    weakSelf.launchResult = result;
    weakSelf.launchError = error;

    [weakSelf executeExperimentsBlocks];
    [weakSelf executeUserBlocks];
    
    NSArray *storeProducts = [weakSelf.storeKitService getLoadedProducts];
    if (!weakSelf.productsLoading && storeProducts.count == 0) {
      [weakSelf loadProducts];
    }
    
    if (!weakSelf.identityInProgress) {
      if (weakSelf.pendingIdentityUserID) {
        [weakSelf identify:weakSelf.pendingIdentityUserID];
      } else if (weakSelf.unhandledLogoutAvailable) {
        [weakSelf handleLogout];
      } else {
        [weakSelf executePermissionBlocks];
      }
    }
    
    if (completion) {
      run_block_on_main(completion, result, error)
    }
    
    if (error) {
      QONVERSION_LOG(@"❗️ Request failed %@", error.description);
    }
  }];
}

- (void)identify:(NSString *)userID {
  self.unhandledLogoutAvailable = NO;
  
  NSString *currentIdentityID = [self.userInfoService obtainCustomIdentityUserID];
  if ([currentIdentityID isEqualToString:userID]) {
    return;
  }
  
  [self resetActualPermissionsCache];
  
  if (!self.launchingFinished) {
    self.pendingIdentityUserID = userID;
    
    return;
  }
  
  self.identityInProgress = YES;
  if (self.launchError) {
    __block __weak QNProductCenterManager *weakSelf = self;

    [weakSelf launch:^(QONLaunchResult * _Nullable result, NSError * _Nullable error) {
      if (error) {
        weakSelf.identityInProgress = NO;
        [weakSelf executePermissionBlocksWithError:error];
      } else {
        [weakSelf processIdentity:userID];
      }
    }];
  } else {
    [self processIdentity:userID];
  }
}

- (void)processIdentity:(NSString *)userID {
  NSString *currentUserID = [self.userInfoService obtainUserID];
  
  __block __weak QNProductCenterManager *weakSelf = self;
  [self.identityManager identify:userID completion:^(NSString *result, NSError * _Nullable error) {
    weakSelf.identityInProgress = NO;
    
    if (error) {
      [weakSelf executePermissionBlocksWithError:error];
      return;
    }
    
    weakSelf.pendingIdentityUserID = nil;
    
    [weakSelf.userInfoService storeCustomIdentityUserID:userID];
    
    if ([currentUserID isEqualToString:result]) {
      [weakSelf executePermissionBlocks];
    } else {
      [[QNAPIClient shared] setUserID:result];
      
      [weakSelf launchWithCompletion:nil];
    }
  }];
}

- (void)logout {
  self.pendingIdentityUserID = nil;
  BOOL isLogoutNeeded = [self.identityManager logoutIfNeeded];
  
  if (isLogoutNeeded) {
    [self.userInfoService storeCustomIdentityUserID:nil];
    self.unhandledLogoutAvailable = YES;
    NSString *userID = [self.userInfoService obtainUserID];
    [[QNAPIClient shared] setUserID:userID];
    
    [self resetActualPermissionsCache];
  }
}

- (void)setPromoPurchasesDelegate:(id<QONPromoPurchasesDelegate>)delegate {
  _promoPurchasesDelegate = delegate;
}

- (void)setPurchasesDelegate:(id<QONEntitlementsUpdateListener>)delegate {
  _purchasesDelegate = delegate;
}

- (void)userInfo:(QNUserInfoCompletionHandler)completion {
  if (!self.launchingFinished) {
    [self.userInfoBlocks addObject:completion];
    return;
  }
  
  completion(self.user, self.launchError);
}

- (void)presentCodeRedemptionSheet {
  [self.storeKitService presentCodeRedemptionSheet];
}

- (void)checkPermissions:(QNEntitlementsCompletionHandler)completion {
  if (!completion) {
    return;
  }
  
  @synchronized (self) {
    if (!_launchingFinished || _identityInProgress) {
      [self.entitlementsBlocks addObject:completion];
      return;
    }
    
    if (_pendingIdentityUserID) {
      [self.entitlementsBlocks addObject:completion];
      [self identify:_pendingIdentityUserID];
      return;
    }
    
    [self preparePermissionsResultWithCompletion:completion];
  }
}

- (void)handleLogout {
  self.unhandledLogoutAvailable = NO;
  [self launchWithCompletion:nil];
}

- (void)purchaseProduct:(QONProduct *)product completion:(QNPurchaseCompletionHandler)completion {
  if (product.offeringID.length > 0) {
    QONOffering *offering = [self.launchResult.offerings offeringForIdentifier:product.offeringID];
    [self purchase:product.qonversionID offeringID:offering.identifier completion:completion];
  } else {
    [self purchase:product.qonversionID offeringID:nil completion:completion];
  }
}

- (void)purchase:(NSString *)productID completion:(QNPurchaseCompletionHandler)completion {
  [self purchase:productID offeringID:nil completion:completion];
}

- (void)purchase:(NSString *)productID offeringID:(NSString *)offeringID completion:(QNPurchaseCompletionHandler)completion {
  @synchronized (self) {
    NSArray *storeProducts = [self.storeKitService getLoadedProducts];
    
    if (self.launchError) {
      __block __weak QNProductCenterManager *weakSelf = self;
      [self launchWithCompletion:^(QONLaunchResult * _Nonnull result, NSError * _Nullable error) {
        QONLaunchResult *cachedResult = [weakSelf cachedLaunchResult];
        if (error && !cachedResult) {
          run_block_on_main(completion, @{}, error, NO);
          return;
        }
        
        if (weakSelf.productsLoading) {
          [weakSelf prepareDelayedPurchase:productID offeringID:offeringID completion:completion];
        } else {
          [weakSelf processPurchase:productID offeringID:offeringID completion:completion];
        }
      }];
    } else if (!self.productsLoading && storeProducts.count == 0) {
      [self prepareDelayedPurchase:productID offeringID:offeringID completion:completion];
      
      [self loadProducts];
    } else {
      [self processPurchase:productID offeringID:offeringID completion:completion];
    }
  }
}

- (void)prepareDelayedPurchase:(NSString *)productID offeringID:offeringID completion:(QNPurchaseCompletionHandler)completion {
  QNProductsCompletionHandler productsCompletion = ^(NSDictionary<NSString *, QONProduct *> *result, NSError  *_Nullable error) {
    if (error) {
      run_block_on_main(completion, @{}, error, NO);
      return;
    }
    
    [self processPurchase:productID offeringID:offeringID completion:completion];
  };
  
  [self.productsBlocks addObject:productsCompletion];
}

- (void)processPurchase:(NSString *)productID offeringID:(NSString *)offeringID completion:(QNPurchaseCompletionHandler)completion {
  QONProduct *product;
  QONExperimentInfo *experimentInfo;
  if (offeringID.length > 0) {
    QONOffering *offering = [self.launchResult.offerings offeringForIdentifier:offeringID];
    
    experimentInfo = offering.experimentInfo;
    
    for (QONProduct *tempProduct in offering.products) {
      if ([tempProduct.qonversionID isEqualToString:productID]) {
        product = tempProduct;
      }
    }
  } else {
    product = [self QNProduct:productID];
  }
  
  if (!product) {
    QONVERSION_LOG(@"❌ product with id: %@ not found", productID);
    run_block_on_main(completion, @{}, [QONErrors errorWithQONErrorCode:QONErrorProductNotFound], NO);
    return;
  }
  
  [self processProductPurchase:product experimentInfo:experimentInfo completion:completion];
}

- (void)processProductPurchase:(QONProduct *)product experimentInfo:(QONExperimentInfo *)experimentInfo completion:(QNPurchaseCompletionHandler)completion {
  if (self.purchasingBlocks[product.storeID]) {
    QONVERSION_LOG(@"Purchasing in process");
    return;
  }
  
  if (product && [_storeKitService purchase:product.storeID]) {
    self.purchasingBlocks[product.storeID] = completion;
    QNProductPurchaseModel *purchaseModel = [[QNProductPurchaseModel alloc] initWithProduct:product experimentInfo:experimentInfo];
    self.purchaseModels[purchaseModel.product.storeID] = purchaseModel;
    
    return;
  }
  
  QONVERSION_LOG(@"❌ Store product with id: %@ not found", product.storeID);
  run_block_on_main(completion, @{}, [QONErrors errorWithQONErrorCode:QONErrorProductNotFound], NO);
}

- (void)restoreWithCompletion:(QNRestoreCompletionHandler)completion {
  self.restorePurchasesBlock = completion;
  [self.storeKitService restore];
}

- (void)preparePermissionsResultWithCompletion:(QNEntitlementsCompletionHandler)completion {
  __block __weak QNProductCenterManager *weakSelf = self;
  
  if (self.launchError || self.unhandledLogoutAvailable) {
    [self launchWithCompletion:^(QONLaunchResult * _Nonnull result, NSError * _Nullable error) {
      weakSelf.unhandledLogoutAvailable = NO;
      NSDictionary<NSString *, QONEntitlement *> *entitlements = result.entitlements;
      NSError *resultError = error;
      if (error && !weakSelf.pendingIdentityUserID) {
        NSDictionary<NSString *, QONEntitlement *> *cachedPermissions = [weakSelf getActualPermissionsForDefaultState:NO];
        entitlements = cachedPermissions ?: entitlements;
        resultError = entitlements ? nil : error;
      }
      
      run_block_on_main(completion, entitlements, resultError);
    }];
  } else {
    run_block_on_main(completion, self.launchResult.entitlements, nil);
  }
}

- (void)executePermissionBlocks {
  [self executePermissionBlocksWithError:nil];
}

- (void)executePermissionBlocksWithError:(NSError *)error {
  @synchronized (self) {
    if (self.entitlementsBlocks.count == 0) {
      return;
    }
    
    NSMutableArray <QNEntitlementsCompletionHandler> *_blocks = [self.entitlementsBlocks copy];
    [self.entitlementsBlocks removeAllObjects];
    
    if (error) {
      for (QNEntitlementsCompletionHandler block in _blocks) {
        run_block_on_main(block, @{}, error);
      }
    } else {
      [self preparePermissionsResultWithCompletion:^(NSDictionary<NSString *,QONEntitlement *> * _Nonnull result, NSError * _Nullable error) {
        for (QNEntitlementsCompletionHandler block in _blocks) {
          run_block_on_main(block, result ?: @{}, error);
        }
      }];
    }
  }
}

- (void)executeExperimentsBlocks {
  @synchronized (self) {
    NSArray <QNExperimentsCompletionHandler> *blocks = [self.experimentsBlocks copy];
    if (blocks.count == 0) {
      return;
    }
    
    [self.experimentsBlocks removeAllObjects];
    
    for (QNExperimentsCompletionHandler block in blocks) {
      run_block_on_main(block, self.launchResult.experiments, self.launchError);
    }
  }
}

- (void)executeUserBlocks {
  @synchronized (self) {
    NSArray <QNUserInfoCompletionHandler> *blocks = [self.userInfoBlocks copy];
    if (blocks.count == 0) {
      return;
    }
    
    [self.userInfoBlocks removeAllObjects];
    
    for (QNUserInfoCompletionHandler block in blocks) {
      run_block_on_main(block, self.user, self.launchError);
    }
  }
}

- (void)executeOfferingsBlocks {
  [self executeOfferingsBlocksWithError:nil];
}

- (void)executeOfferingsBlocksWithError:(NSError * _Nullable)error {
  @synchronized (self) {
    if (self.offeringsBlocks.count == 0) {
      return;
    }
    
    NSArray <QNOfferingsCompletionHandler> *blocks = [self.offeringsBlocks copy];
    
    [self.offeringsBlocks removeAllObjects];
    
    if (error) {
      for (QNOfferingsCompletionHandler block in blocks) {
        run_block_on_main(block, nil, error);
      }
      
      return;
    }
    
    NSError *resultError = error ?: _launchError;
    
    QONOfferings *offerings = [self enrichOfferingsWithStoreProducts];
    resultError = offerings ? nil : resultError;
    
    for (QNOfferingsCompletionHandler block in blocks) {
      run_block_on_main(block, offerings, resultError);
    }
  }
}

- (QONOfferings *)enrichOfferingsWithStoreProducts {
  QONOfferings *offerings = [self getActualOfferings];
  
  [[NSNotificationCenter defaultCenter] removeObserver:self name:kOfferingByIDWasCalledNotificationName object:nil];
  
  for (QONOffering *offering in offerings.availableOfferings) {
    for (QONProduct *product in offering.products) {
      QONProduct *qnProduct = [self productAt:product.qonversionID];
      
      product.skProduct = qnProduct.skProduct;
    }
  }
  
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(offeringByIDWasCalled:) name:kOfferingByIDWasCalledNotificationName object:nil];
  
  return offerings;
  
}

- (void)executeProductsBlocks {
  [self executeProductsBlocksWithError:nil];
}

- (void)executeProductsBlocksWithError:(NSError * _Nullable)error {
  @synchronized (self) {
    NSArray <QNProductsCompletionHandler> *_blocks = [self->_productsBlocks copy];
    if (_blocks.count == 0) {
      return;
    }
    
    [_productsBlocks removeAllObjects];
    
    if (error) {
      for (QNProductsCompletionHandler _block in _blocks) {
        run_block_on_main(_block, @{}, error);
      }
      
      return;
    }
    
    NSArray *products = [(_launchResult.products ?: @{}) allValues];
    
    NSError *resultError;
    
    if (self.launchError) {
      // check if the cache is actual, set the products, and reset the error
      QONLaunchResult *cachedResult = [self cachedLaunchResult];
      products = cachedResult ? cachedResult.products.allValues : products;
      resultError = cachedResult ? nil : self.launchError;
    }
    
    NSDictionary *resultProducts = [self enrichProductsWithStoreProducts:products];
    NSDictionary *result = resultError ? @{} : [resultProducts copy];
    for (QNProductsCompletionHandler _block in _blocks) {
      run_block_on_main(_block, result, resultError);
    }
  }
}

- (NSDictionary<NSString *, QONProduct *> *)enrichProductsWithStoreProducts:(NSArray<QONProduct *> *)products {
  NSMutableDictionary *resultProducts = [[NSMutableDictionary alloc] init];
  for (QONProduct *_product in products) {
    if (!_product.qonversionID) {
      continue;
    }
    
    QONProduct *qnProduct = [self productAt:_product.qonversionID];
    if (qnProduct) {
      [resultProducts setValue:qnProduct forKey:_product.qonversionID];
    }
  }
  
  return [resultProducts copy];
}

- (void)loadProducts {
  if (!self.launchResult || self.productsLoading) {
    return;
  }
  
  self.productsLoading = YES;
  
  NSDictionary<NSString *, QONProduct *> *productsMap = [self getActualProducts];
  NSArray<QONProduct *> *products = productsMap.allValues;
  
  NSMutableSet *productsSet = [[NSMutableSet alloc] init];
  
  if (products) {
    for (QONProduct *product in products) {
      if (product.storeID) {
        [productsSet addObject:product.storeID];
      }
    }
  }

  [_storeKitService loadProducts:productsSet];
}

- (void)products:(QNProductsCompletionHandler)completion {
  @synchronized (self) {
    [self.productsBlocks addObject:completion];
    
    if (self.productsLoading) {
      return;
    }
    
    [self retryLaunchFlowWithCompletion:^{
      [self executeProductsBlocks];
    }];
  }
}

- (void)checkTrialIntroEligibilityForProductIds:(NSArray<NSString *> *)productIds completion:(QNEligibilityCompletionHandler)completion {
  NSArray *uniqueProductIdentifiers = [NSSet setWithArray:productIds].allObjects;
  
  __block __weak QNProductCenterManager *weakSelf = self;
  [self products:^(NSDictionary<NSString *,QONProduct *> * _Nonnull result, NSError * _Nullable error) {
    for (NSString *identifier in uniqueProductIdentifiers) {
      QONProduct *product = result[identifier];
      if (!product) {
        QONVERSION_LOG(@"❌ product with id: %@ not found", identifier);
        run_block_on_main(completion, @{}, [QONErrors errorWithQONErrorCode:QONErrorProductNotFound]);
        return;
      }
    }

    NSArray<QONProduct *> *products = [result.allValues filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(QONProduct *product, NSDictionary *bindings) {
      return product.storeID.length > 0;
    }]];
    
    [weakSelf.apiClient checkTrialIntroEligibilityParamsForProducts:products completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
      QNMapperObject *result = [QNMapper mapperObjectFrom:dict];
      if (result.error) {
        run_block_on_main(completion, @{}, result.error);
        return;
      }
      
      NSDictionary<NSString *, QONIntroEligibility *> *eligibilityData = [QNMapper mapProductsEligibility:result.data];
      NSMutableDictionary<NSString *, QONIntroEligibility *> *resultEligibility = [NSMutableDictionary new];
      
      for (NSString *identifier in uniqueProductIdentifiers) {
        QONIntroEligibility *item = eligibilityData[identifier];
        if (item) {
          resultEligibility[identifier] = item;
        }
      }
      
      run_block_on_main(completion, [resultEligibility copy], nil);
    }];
  }];
}

- (void)retryLaunchFlowWithCompletion:(void(^)(void))completion {
  if (self.launchError) {
    __block __weak QNProductCenterManager *weakSelf = self;
    [self launchWithCompletion:^(QONLaunchResult * _Nonnull result, NSError * _Nullable error) {
      if (weakSelf.productsLoading) {
        return;
      } else {
        completion();
      }
    }];
  } else {
    NSArray *storeProducts = [self.storeKitService getLoadedProducts];
    if (storeProducts.count > 0) {
      completion();
      return;
    } else {
      [self loadProducts];
    }
  }
}

- (void)offerings:(QNOfferingsCompletionHandler)completion {
  @synchronized (self) {
    [self.offeringsBlocks addObject:completion];
    
    __block __weak QNProductCenterManager *weakSelf = self;
    QNProductsCompletionHandler productsCompletion = ^(NSDictionary<NSString *, QONProduct *> *result, NSError  *_Nullable error) {
      [weakSelf executeOfferingsBlocksWithError:error];
    };
    
    [self products:productsCompletion];
  }
}

- (void)experiments:(QNExperimentsCompletionHandler)completion {
  @synchronized (self) {
    [self.experimentsBlocks addObject:completion];
    
    if (!self.launchingFinished) {
      return;
    }
    
    if (self.launchResult) {
      [self executeExperimentsBlocks];
    } else {
      [self launchWithCompletion:nil];
    }
  }
}

- (QONProduct *)productAt:(NSString *)productID {
  QONProduct *product = [self QNProduct:productID];
  if (product) {
    id skProduct = [_storeKitService productAt:product.storeID];
    if (skProduct) {
      [product setSkProduct:skProduct];
    }
    return product;
  }
  return nil;
}

- (QONProduct * _Nullable)QNProduct:(NSString *)productID {
  NSDictionary *products = [self getActualProducts];
  
  return products[productID];
}

- (void)launch:(void (^)(QONLaunchResult * _Nullable result, NSError * _Nullable error))completion {
  __block __weak QNProductCenterManager *weakSelf = self;
  [self.apiClient launchRequest:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
    @synchronized (weakSelf) {
      weakSelf.launchingFinished = YES;
    }

    if (!completion) {
      return;
    }

    if (error) {
      completion([[QONLaunchResult alloc] init], error);
      return;
    }
    
    QNMapperObject *result = [QNMapper mapperObjectFrom:dict];
    if (result.error) {
      completion([[QONLaunchResult alloc] init], result.error);
      return;
    }
    
    QONUser *user = [QNMapper fillUser:result.data];
    weakSelf.user = user;
    
    weakSelf.productsPermissionsRelation = [QNMapper mapProductsPermissionsRelation:result.data];
    [weakSelf.persistentStorage storeObject:weakSelf.productsPermissionsRelation forKey:kKeyQUserDefaultsProductsPermissionsRelation];
    
    QONLaunchResult *launchResult = [QNMapper fillLaunchResult:result.data];
    completion(launchResult, nil);
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      [weakSelf.apiClient processStoredRequests];
    });
  }];
}

- (void)handleFailedTransaction:(SKPaymentTransaction *)transaction forProduct:(SKProduct *)product error:(NSError *)error {
  QNPurchaseCompletionHandler _purchasingBlock = _purchasingBlocks[product.productIdentifier];
  if (_purchasingBlock) {
    run_block_on_main(_purchasingBlock, @{}, error, error.code == QONErrorCancelled);
    @synchronized (self) {
      [_purchasingBlocks removeObjectForKey:product.productIdentifier];
    }
  }
}

// MARK: - QNStoreKitServiceDelegate

- (void)handleRestoredTransactions:(NSArray<SKPaymentTransaction *> *)transactions {
  self.restoredTransactions = [transactions copy];
}

- (void)handleExcessTransactions:(NSArray<SKPaymentTransaction *> *)transactions {
  if (self.launchMode == QONLaunchModeSubscriptionManagement) {
    for (SKPaymentTransaction *transaction in transactions) {
      [self.storeKitService finishTransaction:transaction];
    }
  }
}

- (void)handlePurchasedTransaction:(SKPaymentTransaction *)transaction forProduct:(SKProduct *)product {
  __block __weak QNProductCenterManager *weakSelf = self;
  
  QNProductPurchaseModel *purchaseModel = self.purchaseModels[product.productIdentifier];
  self.purchaseModels[product.productIdentifier] = nil;
  [self.storeKitService receipt:^(NSString * receipt) {
    __block NSURLRequest *request = [weakSelf.apiClient purchaseRequestWith:product transaction:transaction receipt:receipt purchaseModel:purchaseModel completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
      QNPurchaseCompletionHandler _purchasingBlock = weakSelf.purchasingBlocks[product.productIdentifier];
      @synchronized (weakSelf) {
        [weakSelf.purchasingBlocks removeObjectForKey:product.productIdentifier];
      }
      
      if (error && [QNUtils shouldPurchaseRequestBeRetried:error]) {
        [weakSelf.apiClient storeRequestForRetry:request transactionId:transaction.transactionIdentifier];
      } else {
        [weakSelf.apiClient removeStoredRequestForTransactionId:transaction.transactionIdentifier];
      }
     
      if (error && _purchasingBlock) {
        [weakSelf handlePurchaseResult:@{} error:error cancelled:NO transaction:transaction product:product completion:_purchasingBlock];
        return;
      }
      
      QNMapperObject *result = [QNMapper mapperObjectFrom:dict];
      if (result.error && _purchasingBlock) {
        [weakSelf handlePurchaseResult:@{} error:error cancelled:NO transaction:transaction product:product completion:_purchasingBlock];
        return;
      }
      
      QONUser *user = [QNMapper fillUser:result.data];
      weakSelf.user = user;
      
      NSError *resultError = error ?: result.error;
      
      if (weakSelf.launchMode == QONLaunchModeSubscriptionManagement && !resultError) {
        [weakSelf.storeKitService finishTransaction:transaction];
      }
      
      QONLaunchResult *launchResult = [QNMapper fillLaunchResult:result.data];
      
      if (!resultError) {
        @synchronized (weakSelf) {
          weakSelf.launchResult = launchResult;
          weakSelf.launchError = nil;
        }
        
        [weakSelf storeLaunchResultIfNeeded:launchResult];
      }
      
      if (_purchasingBlock) {
        run_block_on_main(_purchasingBlock, launchResult.entitlements, error, NO);
      } else {
        if (transaction.transactionState == SKPaymentTransactionStateRestored) {
          if (!resultError) {
            [weakSelf handleRestoreResult:launchResult.entitlements error:nil];
          }
        } else {
          NSDictionary<NSString *, QONEntitlement *> *resultPermissions = launchResult.entitlements;
          if (resultError) {
            if ([self shouldCalculatePermissionsForError:error]) {
              resultPermissions = [self calculatePermissionsForTransactions:@[transaction] products:@[product]];
              [weakSelf.purchasesDelegate didReceiveUpdatedEntitlements:resultPermissions];
            }
          } else {
            [weakSelf.purchasesDelegate didReceiveUpdatedEntitlements:resultPermissions];
          }
        }
      }
    }];
  }];
}

- (BOOL)shouldCalculatePermissionsForError:(NSError *)error {
  return (error.code >= kInternalServerErrorFirstCode && error.code <= kInternalServerErrorLastCode) || [QNUtils isConnectionError:error];
}

- (void)handleRestoreResult:(NSDictionary<NSString *, QONEntitlement *> *)permissions error:(NSError *)error {
  if (self.restorePurchasesBlock) {
    self.restoredTransactions = nil;
    
    QNRestoreCompletionHandler restorePurchasesBlock = [self.restorePurchasesBlock copy];
    self.restorePurchasesBlock = nil;

    run_block_on_main(restorePurchasesBlock, permissions, error);
  }
}


- (void)handleRestoreCompletedTransactionsFinished {
  if (self.restorePurchasesBlock) {
    NSArray *restoredTransactionsCopy = [self.restoredTransactions copy];
    self.restoredTransactions = nil;
    __block __weak QNProductCenterManager *weakSelf = self;
    [self launch:^(QONLaunchResult * _Nonnull result, NSError * _Nullable error) {
      QNRestoreCompletionHandler restorePurchasesBlock = [weakSelf.restorePurchasesBlock copy];
      weakSelf.restorePurchasesBlock = nil;
      if (error) {
        if ([weakSelf shouldCalculatePermissionsForError:error]) {
          NSArray<SKProduct *> *storeProducts = [weakSelf.storeKitService getLoadedProducts];
          NSDictionary<NSString *, QONEntitlement *> *calculatedPermissions = [weakSelf calculatePermissionsForRestoredTransactions:restoredTransactionsCopy products:storeProducts];
          
          run_block_on_main(restorePurchasesBlock, calculatedPermissions, nil);
        } else {
          run_block_on_main(restorePurchasesBlock, @{}, error);
        }
      } else if (result) {
        [weakSelf storeLaunchResultIfNeeded:result];
        weakSelf.launchResult = result;
        run_block_on_main(restorePurchasesBlock, result.entitlements, error);
      }
    }];
  }
}

- (void)handleRestoreCompletedTransactionsFailed:(NSError *)error {
  if (self.restorePurchasesBlock) {
    QNRestoreCompletionHandler restorePurchasesBlock = [self.restorePurchasesBlock copy];
    self.restorePurchasesBlock = nil;
    run_block_on_main(restorePurchasesBlock, @{}, error);
  }
}

- (void)handleProducts:(NSArray<SKProduct *> *)products {
  @synchronized (self) {
    self->_productsLoading = NO;
  }
  
  [self executeProductsBlocks];
}

- (void)handleProductsRequestFailed:(NSError *)error {
  @synchronized (self) {
    self->_productsLoading = NO;
  }
  
  NSError *er = [QONErrors errorFromTransactionError:error];
  QONVERSION_LOG(@"⚠️ Store products request failed with message: %@", er.description);
  [self executeProductsBlocksWithError:error];
}

- (void)handleDeferredTransaction:(SKPaymentTransaction *)transaction forProduct:(SKProduct *)product {
  NSError *error = [QONErrors deferredTransactionError];
  
  [self handleFailedTransaction:transaction forProduct:product error:error];
}

- (void)handleFailedTransaction:(SKPaymentTransaction *)transaction forProduct:(SKProduct *)product {
  NSError *error = [QONErrors errorFromTransactionError:transaction.error];
  
  [self handleFailedTransaction:transaction forProduct:product error:error];
}

- (BOOL)paymentQueue:(SKPaymentQueue *)queue shouldAddStorePayment:(SKPayment *)payment forProduct:(SKProduct *)product {
  __block __weak QNProductCenterManager *weakSelf = self;
  
  if ([self.promoPurchasesDelegate respondsToSelector:@selector(shouldPurchasePromoProductWithIdentifier:executionBlock:)]) {
    [self.promoPurchasesDelegate shouldPurchasePromoProductWithIdentifier:product.productIdentifier executionBlock:^(QNPurchaseCompletionHandler _Nonnull completion) {
      weakSelf.purchasingBlocks[product.productIdentifier] = completion;
      
      [weakSelf.storeKitService purchaseProduct:product];
    }];
    
    return NO;
  }
  
  return YES;
}

- (void)storePermissions:(NSDictionary<NSString *, QONEntitlement *> *)permissions {
  self.entitlements = permissions;
  NSDate *currentDate = [NSDate date];
  
  [self.persistentStorage storeDouble:currentDate.timeIntervalSince1970 forKey:kKeyQUserDefaultsPermissionsTimestamp];
  [self.persistentStorage storeObject:permissions forKey:kKeyQUserDefaultsPermissions];
}

- (NSDictionary<NSString *, QONEntitlement *> * _Nullable)getActualPermissionsForDefaultState:(BOOL)defaultState {
  if (self.entitlements) {
    return self.entitlements;
  }
  
  NSDictionary<NSString *, QONEntitlement *> *entitlements = [self.persistentStorage loadObjectForKey:kKeyQUserDefaultsPermissions];
  NSTimeInterval cachedPermissionsTimestamp = [self cachedPermissionsTimestamp];
  BOOL isCacheOutdated = [QNUtils isPermissionsOutdatedForDefaultState:defaultState cacheDataTimeInterval:cachedPermissionsTimestamp cacheLifetime:self.cacheLifetime];

  if (!isCacheOutdated) {
    self.entitlements = entitlements;
  }
  
  return self.entitlements;
}

- (NSTimeInterval)cachedPermissionsTimestamp {
  return [self.persistentStorage loadDoubleForKey:kKeyQUserDefaultsPermissionsTimestamp];
}

- (void)resetActualPermissionsCache {
  self.entitlements = nil;
  [self.persistentStorage removeObjectForKey:kKeyQUserDefaultsPermissions];
  [self.persistentStorage removeObjectForKey:kKeyQUserDefaultsPermissionsTimestamp];
}

// MARK: - Move to separate file

- (void)handlePurchaseResult:(NSDictionary<NSString *, QONEntitlement *> *)result
                       error:(NSError *)error
                   cancelled:(BOOL)cancelled
                 transaction:(SKPaymentTransaction *)transaction
                     product:(SKProduct *)product
                  completion:(QNPurchaseCompletionHandler)completion {
  if (error) {
    if ([self shouldCalculatePermissionsForError:error]) {
      NSDictionary<NSString *, QONEntitlement *> *calculatedPermissions = [self calculatePermissionsForTransactions:@[transaction] products:@[product]];
      run_block_on_main(completion, calculatedPermissions, nil, cancelled);
    } else {
      run_block_on_main(completion, @{}, error, cancelled);
    }
  } else {
    run_block_on_main(completion, result, nil, cancelled);
  }
}

- (NSDictionary<NSString *, QONEntitlement *> *)calculatePermissionsForRestoredTransactions:(NSArray<SKPaymentTransaction *> *)transactions
                                                                                 products:(NSArray<SKProduct *> *)products {
  NSSortDescriptor *dateDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"transactionDate" ascending:NO];
  NSArray *sortDescriptors = [NSArray arrayWithObject:dateDescriptor];
  NSArray *sortedTransactions = [transactions sortedArrayUsingDescriptors:sortDescriptors];

  NSMutableDictionary *resultTransactionsDict = [NSMutableDictionary new];
  for (SKPaymentTransaction *transaction in sortedTransactions) {
    if (resultTransactionsDict[transaction.payment.productIdentifier] == nil) {
      resultTransactionsDict[transaction.payment.productIdentifier] = transaction;
    }
  }

  return [self calculatePermissionsForTransactions:resultTransactionsDict.allValues products:products];
}

- (NSDictionary<NSString *, QONEntitlement *> *)calculatePermissionsForTransactions:(NSArray<SKPaymentTransaction *> *)transactions
                                                                         products:(NSArray<SKProduct *> *)products {
  NSMutableDictionary<NSString *, QONEntitlement *> *resultPermissions = [NSMutableDictionary new];
  NSMutableDictionary<NSString *, SKProduct *> *productsMap = [NSMutableDictionary new];

  for (SKProduct *product in products) {
    productsMap[product.productIdentifier] = product;
  }

  NSMutableDictionary<NSString *, QONProduct *> *qonversionProductsMap = [NSMutableDictionary new];
  QONLaunchResult *launchResult = self.launchError ? [self cachedLaunchResult] : self.launchResult;
  for (QONProduct *value in launchResult.products.allValues) {
    if (value.storeID.length > 0) {
      qonversionProductsMap[value.storeID] = value;
    }
  }

  if (@available(iOS 11.2, macOS 10.13.2, watchOS 6.2, tvOS 11.2, *)) {
    for (SKPaymentTransaction *transaction in transactions) {
      SKProduct *product = productsMap[transaction.payment.productIdentifier];
      NSDate *expirationDate = [QNUtils calculateExpirationDateForPeriod:product.subscriptionPeriod fromDate:transaction.transactionDate];
      if (!expirationDate || [expirationDate compare:[NSDate date]] == NSOrderedDescending) {
        NSDictionary<NSString *, QONEntitlement *> *entitlements = [self createPermissionsForProductsMap:qonversionProductsMap transaction:transaction expirationDate:expirationDate];

        [resultPermissions addEntriesFromDictionary:entitlements];
      }
    }
  } else {
    for (SKPaymentTransaction *transaction in transactions) {
      QONProduct *qonversionProduct = qonversionProductsMap[transaction.payment.productIdentifier];
      NSDate *expirationDate = [QNUtils calculateExpirationDateForProduct:qonversionProduct fromDate:transaction.transactionDate];
      if (!expirationDate || [expirationDate compare:[NSDate date]] == NSOrderedDescending) {
        NSDictionary<NSString *, QONEntitlement *> *entitlements = [self createPermissionsForProductsMap:qonversionProductsMap transaction:transaction expirationDate:expirationDate];

        [resultPermissions addEntriesFromDictionary:entitlements];
      }
    }
  }

  resultPermissions = [self mergePermissions:resultPermissions];
  
  NSDictionary<NSString *, QONEntitlement *> *resultPermissionsCopy = [resultPermissions copy];

  [self storePermissions:resultPermissionsCopy];

  return resultPermissionsCopy;
}

- (NSMutableDictionary<NSString *, QONEntitlement *> *)mergePermissions:(NSMutableDictionary *)permissions {
  NSDictionary *currentPermissions = self.entitlements.count > 0 ? self.entitlements : [self getActualPermissionsForDefaultState:NO];
  NSMutableDictionary<NSString *, QONEntitlement *> *resultEntitlements = [currentPermissions mutableCopy];

  for (QONEntitlement *entitlement in permissions.allValues) {
    QONEntitlement *currentEntitlement = resultEntitlements[entitlement.entitlementID];
    if (currentEntitlement && (!currentEntitlement.isActive || [entitlement.expirationDate compare:currentEntitlement.expirationDate] == NSOrderedDescending)) {
      resultEntitlements[entitlement.entitlementID] = entitlement;
    }
  }

  return resultEntitlements;
}

- (NSDictionary<NSString *, QONEntitlement *> *)createPermissionsForProductsMap:(NSDictionary *)productsMap
                                                                  transaction:(SKPaymentTransaction *)transaction
                                                               expirationDate:(NSDate *)expirationDate {
  NSMutableDictionary<NSString *, QONEntitlement *> *resultPermissions = [NSMutableDictionary new];

  QONProduct *qonversionProduct = productsMap[transaction.payment.productIdentifier];

  NSArray<NSString *> *entitlementsIds = self.productsPermissionsRelation[qonversionProduct.qonversionID];
  for (NSString *entitlementId in entitlementsIds) {
    QONEntitlement *entitlement = [self createPermissionsForId:entitlementId qonversionProduct:qonversionProduct transaction:transaction expirationDate:expirationDate];

    resultPermissions[entitlement.entitlementID] = entitlement;
  }

  return [resultPermissions copy];
}

- (QONEntitlement *)createPermissionsForId:(NSString *)permissionId
                       qonversionProduct:(QONProduct *)qonversionProduct
                             transaction:(SKPaymentTransaction *)transaction
                          expirationDate:(NSDate *)expirationDate {
  QONEntitlement *entitlement = [[QONEntitlement alloc] init];
  entitlement.entitlementID = permissionId;
  entitlement.isActive = YES;
  entitlement.renewState = QONEntitlementRenewStateUnknown;
  entitlement.source = QONEntitlementSourceAppStore;
  entitlement.productID = qonversionProduct.qonversionID;
  entitlement.startedDate = transaction.transactionDate;
  entitlement.expirationDate = expirationDate;

  return entitlement;
}

@end
