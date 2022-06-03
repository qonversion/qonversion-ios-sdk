#import "QNProductCenterManager.h"
#import "QNUserDefaultsStorage.h"
#import "QNStoreKitService.h"
#import "QNAPIClient.h"
#import "QNMapper.h"
#import "QNLaunchResult.h"
#import "QNMapperObject.h"
#import "QNProduct.h"
#import "QNErrors.h"
#import "QNPromoPurchasesDelegate.h"
#import "QNPurchasesDelegate.h"
#import "QNOfferings.h"
#import "QNOffering.h"
#import "QNIntroEligibility.h"
#import "QNServicesAssembly.h"
#import "QNIdentityManagerInterface.h"
#import "QNUserInfoServiceInterface.h"
#import "QNProductPurchaseModel.h"
#import "QNExperimentInfo.h"
#import "QNDevice.h"
#import "QNInternalConstants.h"

static NSString * const kLaunchResult = @"qonversion.launch.result";
static NSString * const kLaunchResultTimeStamp = @"qonversion.launch.result.timestamp";
static NSString * const kUserDefaultsSuiteName = @"qonversion.product-center.suite";

@interface QNProductCenterManager() <QNStoreKitServiceDelegate>

@property (nonatomic, weak) id<QNPurchasesDelegate> purchasesDelegate;
@property (nonatomic, weak) id<QNPromoPurchasesDelegate> promoPurchasesDelegate;

@property (nonatomic, strong) QNStoreKitService *storeKitService;
@property (nonatomic, strong) QNUserDefaultsStorage *persistentStorage;
@property (nonatomic, strong) id<QNIdentityManagerInterface> identityManager;
@property (nonatomic, strong) id<QNUserInfoServiceInterface> userInfoService;

@property (nonatomic, copy) QNRestoreCompletionHandler restorePurchasesBlock;

@property (nonatomic, strong) NSMutableDictionary <NSString *, QNPurchaseCompletionHandler> *purchasingBlocks;
@property (nonatomic, strong) NSMutableDictionary <NSString *, QNProductPurchaseModel *> *purchaseModels;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<QNPermissionCompletionHandler> *> *permissionsBlocks;
@property (nonatomic, strong) NSMutableArray<QNProductsCompletionHandler> *productsBlocks;
@property (nonatomic, strong) NSMutableArray<QNOfferingsCompletionHandler> *offeringsBlocks;
@property (nonatomic, strong) NSMutableArray<QNExperimentsCompletionHandler> *experimentsBlocks;
@property (nonatomic, strong) NSMutableArray<QNUserInfoCompletionHandler> *userInfoBlocks;
@property (atomic, strong) NSMutableArray<SKPaymentTransaction *> *restoredTransactions;
@property (nonatomic, strong) QNAPIClient *apiClient;

@property (nonatomic, strong) QNLaunchResult *launchResult;
@property (nonatomic, copy) NSDictionary<NSString *, QNPermission *> *permissions;
@property (nonatomic, strong) NSError *launchError;
@property (nonatomic, strong) QNUser *user;

@property (nonatomic, assign) BOOL launchingFinished;
@property (nonatomic, assign) BOOL productsLoading;
@property (nonatomic, assign) BOOL forcePermissionsRetry;
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
    _forcePermissionsRetry = YES;
    _launchError = nil;
    _launchResult = nil;
    
    QNServicesAssembly *servicesAssembly = [QNServicesAssembly new];
    
    _userInfoService = [servicesAssembly userInfoService];
    _identityManager = [servicesAssembly identityManager];
    
    _apiClient = [QNAPIClient shared];
    _storeKitService = [[QNStoreKitService alloc] initWithDelegate:self];
    
    _persistentStorage = [[QNUserDefaultsStorage alloc] init];
    [_persistentStorage setUserDefaults:[[NSUserDefaults alloc] initWithSuiteName:kUserDefaultsSuiteName]];
    
    _purchaseModels = [NSMutableDictionary new];
    _purchasingBlocks = [NSMutableDictionary new];
    _permissionsBlocks = [NSMutableDictionary new];
    _productsBlocks = [NSMutableArray new];
    _offeringsBlocks = [NSMutableArray new];
    _experimentsBlocks = [NSMutableArray new];
    _userInfoBlocks = [NSMutableArray new];
  }
  
  return self;
}

- (void)offeringByIDWasCalled:(NSNotification *)notification {
  QNOffering *offering = notification.object;
  BOOL isOfferingClass = [offering isMemberOfClass:[QNOffering class]];
  if (isOfferingClass) {
    offering.experimentInfo.attached = YES;
    [self.apiClient sendOfferingEvent:offering];
  }
}

- (void)storeLaunchResultIfNeeded:(QNLaunchResult *)launchResult {
  if (launchResult.timestamp > 0) {
    NSDate *currentDate = [NSDate date];
    
    [self.persistentStorage storeDouble:currentDate.timeIntervalSince1970 forKey:kLaunchResultTimeStamp];
    [self.persistentStorage storeObject:launchResult forKey:kLaunchResult];
  }
}

- (QNLaunchResult * _Nullable)actualCachedLaunchResult {
  QNLaunchResult *result = [self.persistentStorage loadObjectForKey:kLaunchResult];
  NSTimeInterval cachedLaunchResultTimestamp = [self cachedLaunchResultTimestamp];
  BOOL isCacheOutdated = [QNUtils isCacheOutdated:cachedLaunchResultTimestamp];
  
  return isCacheOutdated ? nil : result;
}

- (void)storePermissions:(NSDictionary<NSString *, QNPermission *> *)permissions {
  NSDate *currentDate = [NSDate date];
  
  [self.persistentStorage storeDouble:currentDate.timeIntervalSince1970 forKey:kKeyQUserDefaultsPermissionsTimestamp];
  [self.persistentStorage storeObject:permissions forKey:kKeyQUserDefaultsPermissions];
}

- (NSDictionary<NSString *, QNPermission *> * _Nullable)getActualPermissionsForDefaultState:(BOOL)defaultState {
  NSDictionary<NSString *, QNPermission *> *permissions = self.permissions ?: [self.persistentStorage loadObjectForKey:kKeyQUserDefaultsPermissions];
  NSTimeInterval cachedLaunchResultTimestamp = [self cachedPermissionsTimestamp];
  BOOL isCacheOutdated = [QNUtils isPermissionsOutdatedForDefaultState:defaultState cacheDataTimeInterval:cachedLaunchResultTimestamp];
  
  return isCacheOutdated ? nil : permissions;
}

- (void)resetActualPermissionsCache {
  [self.persistentStorage removeObjectForKey:kKeyQUserDefaultsPermissions];
  [self.persistentStorage removeObjectForKey:kKeyQUserDefaultsPermissionsTimestamp];
}

- (NSTimeInterval)cachedLaunchResultTimestamp {
  return [self.persistentStorage loadDoubleForKey:kLaunchResultTimeStamp];
}

- (NSTimeInterval)cachedPermissionsTimestamp {
  return [self.persistentStorage loadDoubleForKey:kKeyQUserDefaultsPermissionsTimestamp];
}

- (NSDictionary<NSString *, QNProduct *> *)getActualProducts {
  NSDictionary *products = _launchResult.products ?: @{};
  
  if (self.launchError) {
    QNLaunchResult *cachedResult = [self actualCachedLaunchResult];
    products = cachedResult ? cachedResult.products : products;
  }
  
  return products;
}

- (QNOfferings * _Nullable)getActualOfferings {
  QNOfferings *offerings = self.launchResult.offerings ?: nil;
  
  if (self.launchError) {
    QNLaunchResult *cachedResult = [self actualCachedLaunchResult];
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
  
  [self launch:^(QNLaunchResult * _Nonnull result, NSError * _Nullable error) {
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
  self.pendingIdentityUserID = userID;
  if (!self.launchingFinished) {
    return;
  }
  
  self.identityInProgress = YES;
  if (self.launchError) {
    __block __weak QNProductCenterManager *weakSelf = self;

    [weakSelf launch:^(QNLaunchResult * _Nullable result, NSError * _Nullable error) {
      if (error) {
        weakSelf.identityInProgress = NO;
        NSString *userID = [weakSelf.userInfoService obtainUserID];
        [weakSelf executePermissionBlocks:nil error:error userID:userID];
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
  
  NSString *currentIdentityID = [self.userInfoService obtainCustomIdentityUserID];
  
  if ([currentIdentityID isEqualToString:userID]) {
    self.pendingIdentityUserID = nil;
    self.identityInProgress = NO;
    NSDictionary *actualPermissions = [self getActualPermissionsForDefaultState:YES];
    if (actualPermissions) {
      [self executePermissionBlocks:actualPermissions userID:currentUserID];
    } else {
      [self checkPermissions:^(NSDictionary<NSString *,QNPermission *> * _Nonnull result, NSError * _Nullable error) {}];
    }
    
    return;
  }
  
  __block __weak QNProductCenterManager *weakSelf = self;
  [self.identityManager identify:userID completion:^(NSString *result, NSError * _Nullable error) {
    weakSelf.identityInProgress = NO;
    
    NSString *identityID = [weakSelf.pendingIdentityUserID copy];
    weakSelf.pendingIdentityUserID = nil;
    
    if (error) {
      [weakSelf executePermissionBlocks:nil error:error userID:userID];

      return;
    }
    
    if (![result isEqualToString:currentUserID]) {
      [weakSelf resetActualPermissionsCache];
    }
    
    [[QNAPIClient shared] setUserID:result];
    
    NSMutableArray *identityIdCallbacks = weakSelf.permissionsBlocks[identityID];
    if (identityIdCallbacks) {
      weakSelf.permissionsBlocks[weakSelf.pendingIdentityUserID] = nil;
      NSMutableArray *resultIdCallbacks = weakSelf.permissionsBlocks[result] ?: [NSMutableArray new];
      NSInteger previousCallbacksCount = resultIdCallbacks.count;
      [resultIdCallbacks addObjectsFromArray:identityIdCallbacks];
      weakSelf.permissionsBlocks[result] = resultIdCallbacks;
      if (previousCallbacksCount == 0) {
        [weakSelf checkPermissions:^(NSDictionary<NSString *,QNPermission *> * _Nonnull result, NSError * _Nullable error) {}];
      }
    }
  }];
}

- (void)logout {
  self.pendingIdentityUserID = nil;
  
  BOOL isLogoutNeeded = [self.identityManager logoutIfNeeded];
  
  if (isLogoutNeeded) {
    self.unhandledLogoutAvailable = YES;
    NSString *userID = [self.userInfoService obtainUserID];
    [[QNAPIClient shared] setUserID:userID];
    
    [self resetActualPermissionsCache];
  }
}

- (void)setPromoPurchasesDelegate:(id<QNPromoPurchasesDelegate>)delegate {
  _promoPurchasesDelegate = delegate;
}

- (void)setPurchasesDelegate:(id<QNPurchasesDelegate>)delegate {
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

- (void)checkPermissions:(QNPermissionCompletionHandler)completion {
  if (!completion) {
    return;
  }
  
  @synchronized (self) {
    BOOL isRequestInProgress = NO;
    if (self.pendingIdentityUserID) {
      NSMutableArray *callbacks = self.permissionsBlocks[self.pendingIdentityUserID] ?: [NSMutableArray new];
      [callbacks addObject:completion];
      
      self.permissionsBlocks[self.pendingIdentityUserID] = callbacks;
      
      return;
    }
    
    NSString *userID = [self.userInfoService obtainUserID];
    
    NSDictionary<NSString *, QNPermission *> *actualPermissions = [self getActualPermissionsForDefaultState:YES];
    if (actualPermissions && !self.forcePermissionsRetry) {
      run_block_on_main(completion, actualPermissions, nil);
      
      return;
    }
    
    NSMutableArray *callbacks = self.permissionsBlocks[userID] ?: [NSMutableArray new];
    
    isRequestInProgress = callbacks.count > 0;
    
    [callbacks addObject:completion];
    
    self.permissionsBlocks[userID] = callbacks;
    
    if (isRequestInProgress) {
      return;
    }
  }
  
  __block __weak QNProductCenterManager *weakSelf = self;
  
  [self.apiClient obtainEntitlements:^(NSDictionary * _Nullable result, NSError * _Nullable error) {
    NSString *userID = [self.userInfoService obtainUserID];
    if (error.code == kNotFoundErrorCode) {
      if (weakSelf.launchResult || weakSelf.launchError) {
        [weakSelf launchWithCompletion:nil];
      }
      [weakSelf executePermissionBlocks:nil userID:userID];
    } else if (error) {
      [weakSelf handlePermissionsError:error userID:userID];
    } else {
      weakSelf.forcePermissionsRetry = NO;
      NSDictionary<NSString *, QNPermission *> *permissions = [QNMapper fillPermissions:result];
      weakSelf.permissions = permissions;
      [weakSelf storePermissions:permissions];
      [weakSelf executePermissionBlocks:permissions userID:userID];
    }
  }];
}

- (void)handlePermissionsError:(NSError *)error userID:(NSString *)userID {
  if (self.forcePermissionsRetry) {
    [self executePermissionBlocks:nil error:error userID:userID];
  } else {
    NSDictionary<NSString *, QNPermission *> *cachedPermissions = [self getActualPermissionsForDefaultState:NO];
    if (cachedPermissions) {
      [self executePermissionBlocks:cachedPermissions error:nil userID:userID];
    } else {
      [self executePermissionBlocks:nil error:error userID:userID];
    }
  }
}

- (void)handleLogout {
  self.unhandledLogoutAvailable = NO;
  [self launchWithCompletion:nil];
}

- (void)purchaseProduct:(QNProduct *)product completion:(QNPurchaseCompletionHandler)completion {
  if (product.offeringID.length > 0) {
    QNOffering *offering = [self.launchResult.offerings offeringForIdentifier:product.offeringID];
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
      [self launchWithCompletion:^(QNLaunchResult * _Nonnull result, NSError * _Nullable error) {
        QNLaunchResult *cachedResult = [weakSelf actualCachedLaunchResult];
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
  QNProductsCompletionHandler productsCompletion = ^(NSDictionary<NSString *, QNProduct *> *result, NSError  *_Nullable error) {
    if (error) {
      run_block_on_main(completion, @{}, error, NO);
      return;
    }
    
    [self processPurchase:productID offeringID:offeringID completion:completion];
  };
  
  [self.productsBlocks addObject:productsCompletion];
}

- (void)processPurchase:(NSString *)productID offeringID:(NSString *)offeringID completion:(QNPurchaseCompletionHandler)completion {
  QNProduct *product;
  QNExperimentInfo *experimentInfo;
  if (offeringID.length > 0) {
    QNOffering *offering = [self.launchResult.offerings offeringForIdentifier:offeringID];
    
    experimentInfo = offering.experimentInfo;
    
    for (QNProduct *tempProduct in offering.products) {
      if ([tempProduct.qonversionID isEqualToString:productID]) {
        product = tempProduct;
      }
    }
  } else {
    product = [self QNProduct:productID];
  }
  
  if (!product) {
    QONVERSION_LOG(@"❌ product with id: %@ not found", productID);
    run_block_on_main(completion, @{}, [QNErrors errorWithQNErrorCode:QNErrorProductNotFound], NO);
    return;
  }
  
  [self processProductPurchase:product experimentInfo:experimentInfo completion:completion];
}

- (void)processProductPurchase:(QNProduct *)product experimentInfo:(QNExperimentInfo *)experimentInfo completion:(QNPurchaseCompletionHandler)completion {
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
  run_block_on_main(completion, @{}, [QNErrors errorWithQNErrorCode:QNErrorProductNotFound], NO);
}

- (void)restoreWithCompletion:(QNRestoreCompletionHandler)completion {
  self.restorePurchasesBlock = completion;
  [self.storeKitService restore];
}

- (void)executePermissionBlocks:(NSDictionary *)permissions userID:(NSString *)userID {
  [self executePermissionBlocks:permissions error:nil userID:userID];
}

- (void)executePermissionBlocks:(NSDictionary *)permissions error:(NSError *)error userID:(NSString *)userID {
  @synchronized (self) {
    if (self.permissionsBlocks.count == 0) {
      return;
    }
    
    NSDictionary<NSString *, NSMutableArray<QNPermissionCompletionHandler> *> *blocks = [self.permissionsBlocks copy];
    [self.permissionsBlocks removeAllObjects];
    
    for (NSString *key in blocks.allKeys) {
      NSMutableArray *completions = blocks[key];
      
      for (QNPermissionCompletionHandler completion in completions) {
        if (error) {
          run_block_on_main(completion, @{}, error);
        } else {
          run_block_on_main(completion, permissions ?: @{}, nil);
        }
      }
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
    
    QNOfferings *offerings = [self enrichOfferingsWithStoreProducts];
    resultError = offerings ? nil : resultError;
    
    for (QNOfferingsCompletionHandler block in blocks) {
      run_block_on_main(block, offerings, resultError);
    }
  }
}

- (QNOfferings *)enrichOfferingsWithStoreProducts {
  QNOfferings *offerings = [self getActualOfferings];
  
  [[NSNotificationCenter defaultCenter] removeObserver:self name:kOfferingByIDWasCalledNotificationName object:nil];
  
  for (QNOffering *offering in offerings.availableOfferings) {
    for (QNProduct *product in offering.products) {
      QNProduct *qnProduct = [self productAt:product.qonversionID];
      
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
      QNLaunchResult *cachedResult = [self actualCachedLaunchResult];
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

- (NSDictionary<NSString *, QNProduct *> *)enrichProductsWithStoreProducts:(NSArray<QNProduct *> *)products {
  NSMutableDictionary *resultProducts = [[NSMutableDictionary alloc] init];
  for (QNProduct *_product in products) {
    if (!_product.qonversionID) {
      continue;
    }
    
    QNProduct *qnProduct = [self productAt:_product.qonversionID];
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
  
  NSDictionary<NSString *, QNProduct *> *productsMap = [self getActualProducts];
  NSArray<QNProduct *> *products = productsMap.allValues;
  
  NSMutableSet *productsSet = [[NSMutableSet alloc] init];
  
  if (products) {
    for (QNProduct *product in products) {
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
  [self products:^(NSDictionary<NSString *,QNProduct *> * _Nonnull result, NSError * _Nullable error) {
    for (NSString *identifier in uniqueProductIdentifiers) {
      QNProduct *product = result[identifier];
      if (!product) {
        QONVERSION_LOG(@"❌ product with id: %@ not found", identifier);
        run_block_on_main(completion, @{}, [QNErrors errorWithQNErrorCode:QNErrorProductNotFound]);
        return;
      }
    }
    
    [weakSelf.apiClient checkTrialIntroEligibilityParamsForProducts:result.allValues completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
      QNMapperObject *result = [QNMapper mapperObjectFrom:dict];
      if (result.error) {
        run_block_on_main(completion, @{}, result.error);
        return;
      }
      
      NSDictionary<NSString *, QNIntroEligibility *> *eligibilityData = [QNMapper mapProductsEligibility:result.data];
      NSMutableDictionary<NSString *, QNIntroEligibility *> *resultEligibility = [NSMutableDictionary new];
      
      for (NSString *identifier in uniqueProductIdentifiers) {
        QNIntroEligibility *item = eligibilityData[identifier];
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
    [self launchWithCompletion:^(QNLaunchResult * _Nonnull result, NSError * _Nullable error) {
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
    QNProductsCompletionHandler productsCompletion = ^(NSDictionary<NSString *, QNProduct *> *result, NSError  *_Nullable error) {
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

- (QNProduct *)productAt:(NSString *)productID {
  QNProduct *product = [self QNProduct:productID];
  if (product) {
    id skProduct = [_storeKitService productAt:product.storeID];
    if (skProduct) {
      [product setSkProduct:skProduct];
    }
    return product;
  }
  return nil;
}

- (QNProduct * _Nullable)QNProduct:(NSString *)productID {
  NSDictionary *products = [self getActualProducts];
  
  return products[productID];
}

- (void)launch:(void (^)(QNLaunchResult * _Nullable result, NSError * _Nullable error))completion {
  __block __weak QNProductCenterManager *weakSelf = self;
  [self.apiClient launchRequest:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
    @synchronized (weakSelf) {
      weakSelf.launchingFinished = YES;
    }

    if (!completion) {
      return;
    }

    if (error) {
      completion([[QNLaunchResult alloc] init], error);
      return;
    }
    
    QNMapperObject *result = [QNMapper mapperObjectFrom:dict];
    if (result.error) {
      completion([[QNLaunchResult alloc] init], result.error);
      return;
    }
    
    weakSelf.forcePermissionsRetry = NO;
    
    QNUser *user = [QNMapper fillUser:result.data];
    weakSelf.user = user;
    
    QNLaunchResult *launchResult = [QNMapper fillLaunchResult:result.data];
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
    run_block_on_main(_purchasingBlock, @{}, error, error.code == QNErrorCancelled);
    @synchronized (self) {
      [_purchasingBlocks removeObjectForKey:product.productIdentifier];
    }
  }
}

// MARK: - QNStoreKitServiceDelegate

- (void)handleRestoredTransactions:(NSArray<SKPaymentTransaction *> *)transactions {
  self.restoredTransactions = [transactions mutableCopy];
}

- (void)handlePurchasedTransaction:(SKPaymentTransaction *)transaction forProduct:(SKProduct *)product {
  __block __weak QNProductCenterManager *weakSelf = self;
  
  QNProductPurchaseModel *purchaseModel = self.purchaseModels[product.productIdentifier];
  self.purchaseModels[product.productIdentifier] = nil;
  [self.storeKitService receipt:^(NSString * receipt) {
    [weakSelf.apiClient purchaseRequestWith:product transaction:transaction receipt:receipt purchaseModel:purchaseModel completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
      QNPurchaseCompletionHandler _purchasingBlock = weakSelf.purchasingBlocks[product.productIdentifier];
      @synchronized (weakSelf) {
        [weakSelf.purchasingBlocks removeObjectForKey:product.productIdentifier];
      }
      
      weakSelf.forcePermissionsRetry = error != nil;
      
      if (error && _purchasingBlock) {
        run_block_on_main(_purchasingBlock, @{}, error, NO);
        return;
      } else if (!error) {
        QNMapperObject *result = [QNMapper mapperObjectFrom:dict];
        weakSelf.forcePermissionsRetry = result.error != nil;
        
        if (result.error && _purchasingBlock) {
          run_block_on_main(_purchasingBlock, @{}, result.error, NO);
          return;
        }
        
        [weakSelf.storeKitService finishTransaction:transaction];
        
        QNUser *user = [QNMapper fillUser:result.data];
        weakSelf.user = user;
        
        QNLaunchResult *launchResult = [QNMapper fillLaunchResult:result.data];
        NSDictionary *permissions = [launchResult performSelector:@selector(permissions)];
        weakSelf.permissions = permissions;
        [weakSelf storePermissions:permissions];
        @synchronized (weakSelf) {
          weakSelf.launchResult = launchResult;
          weakSelf.launchError = nil;
        }
        
        [weakSelf storeLaunchResultIfNeeded:launchResult];
      }
      
      [weakSelf checkPermissions:^(NSDictionary<NSString *,QNPermission *> * _Nonnull result, NSError * _Nullable error) {
        if (_purchasingBlock) {
          run_block_on_main(_purchasingBlock, result, error, NO);
        } else {
          if (transaction.transactionState != SKPaymentTransactionStateRestored && !error) {
            [weakSelf.purchasesDelegate qonversionDidReceiveUpdatedPermissions:result];
          } else {
            if (error) {
              NSLock *arrayLock = [NSLock new];
              [arrayLock lock];
              if ([weakSelf.restoredTransactions containsObject:transaction]) {
                [weakSelf.restoredTransactions removeObject:transaction];
                
                if (weakSelf.restoredTransactions.count == 0) {
                  [weakSelf handleRestoreResult:nil error:error];
                }
              }
              [arrayLock unlock];
            } else {
              weakSelf.restoredTransactions = nil;
              [weakSelf handleRestoreResult:result error:nil];
            }
          }
        }
      }];
    }];
  }];
}

- (void)handleRestoreResult:(NSDictionary<NSString *, QNPermission *> *)permissions error:(NSError *)error {
  if (self.restorePurchasesBlock) {
    QNRestoreCompletionHandler restorePurchasesBlock = [self.restorePurchasesBlock copy];
    self.restorePurchasesBlock = nil;
    
    run_block_on_main(restorePurchasesBlock, permissions, error);
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
  
  NSError *er = [QNErrors errorFromTransactionError:error];
  QONVERSION_LOG(@"⚠️ Store products request failed with message: %@", er.description);
  [self executeProductsBlocksWithError:error];
}

- (void)handleDeferredTransaction:(SKPaymentTransaction *)transaction forProduct:(SKProduct *)product {
  NSError *error = [QNErrors deferredTransactionError];
  
  [self handleFailedTransaction:transaction forProduct:product error:error];
}

- (void)handleFailedTransaction:(SKPaymentTransaction *)transaction forProduct:(SKProduct *)product {
  NSError *error = [QNErrors errorFromTransactionError:transaction.error];
  
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

@end
