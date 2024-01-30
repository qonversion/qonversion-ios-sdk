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
#import "QNDevice.h"
#import "QNInternalConstants.h"
#import "QONUser+Protected.h"
#import "QONStoreKit2PurchaseModel.h"

#if TARGET_OS_IOS
#import "QONAutomations.h"
#endif

static NSString * const kLaunchResult = @"qonversion.launch.result";
static NSString * const kLaunchResultTimeStamp = @"qonversion.launch.result.timestamp";
static NSString * const kUserDefaultsSuiteName = @"qonversion.product-center.suite";

@interface QNProductCenterManager() <QNStoreKitServiceDelegate>

@property (nonatomic, weak) id<QONEntitlementsUpdateListener> purchasesDelegate;
@property (nonatomic, weak) id<QONPromoPurchasesDelegate> promoPurchasesDelegate;

@property (nonatomic, strong) QNStoreKitService *storeKitService;
@property (nonatomic, strong) id<QNLocalStorage> persistentStorage;
@property (nonatomic, strong) id<QNIdentityManagerInterface> identityManager;
@property (nonatomic, strong) id<QNUserInfoServiceInterface> userInfoService;

@property (nonatomic, copy) NSArray<SKPaymentTransaction *> *restoredTransactions;

@property (nonatomic, strong) NSMutableDictionary <NSString *, QONPurchaseCompletionHandler> *purchasingBlocks;
@property (nonatomic, strong) NSMutableArray<QNRestoreCompletionHandler> *restorePurchasesBlocks;
@property (nonatomic, strong) NSMutableArray<QONEntitlementsCompletionHandler> *entitlementsBlocks;
@property (nonatomic, strong) NSMutableArray<QONProductsCompletionHandler> *productsBlocks;
@property (nonatomic, strong) NSMutableArray<QONOfferingsCompletionHandler> *offeringsBlocks;
@property (nonatomic, strong) NSMutableArray<QONUserInfoCompletionHandler> *userInfoBlocks;
@property (nonatomic, assign) QONEntitlementsCacheLifetime cacheLifetime;
@property (nonatomic, copy) NSDictionary<NSString *, NSArray *> *productsEntitlementsRelation;
@property (nonatomic, copy) NSDictionary<NSString *, QONEntitlement *> *entitlements;
@property (nonatomic, strong) QNAPIClient *apiClient;

@property (nonatomic, strong) QONLaunchResult *launchResult;
@property (nonatomic, strong) NSError *launchError;
@property (nonatomic, strong) QONUser *user;

@property (nonatomic, assign) BOOL launchingFinished;
@property (nonatomic, assign) BOOL productsLoading;
@property (nonatomic, assign) BOOL restoreInProgress;
@property (nonatomic, assign) BOOL awaitingRestoreResult;
@property (nonatomic, assign) BOOL identityInProgress;
@property (nonatomic, assign) BOOL unhandledLogoutAvailable;
@property (nonatomic, copy) NSString *pendingIdentityUserID;

@end

@implementation QNProductCenterManager

- (instancetype)initWithUserInfoService:(id<QNUserInfoServiceInterface>)userInfoService identityManager:(id<QNIdentityManagerInterface>)identityManager localStorage:(id<QNLocalStorage>)localStorage {
  self = super.init;
  if (self) {
    _launchingFinished = NO;
    _productsLoading = NO;
    _launchError = nil;
    _launchResult = nil;
    _cacheLifetime = QONEntitlementsCacheLifetimeMonth;

#if TARGET_OS_IOS
    [QONAutomations sharedInstance];
#endif
    [self supportMigrationFromOldVersions];
    
    _userInfoService = userInfoService;
    _identityManager = identityManager;
    
    _apiClient = [QNAPIClient shared];
    _storeKitService = [[QNStoreKitService alloc] initWithDelegate:self];
    
    _persistentStorage = localStorage;
    [self transferCachedPermissionsIfNeeded];
    _productsEntitlementsRelation = [_persistentStorage loadObjectForKey:kKeyQUserDefaultsProductsPermissionsRelation];
    
    _purchasingBlocks = [NSMutableDictionary new];
    _restorePurchasesBlocks = [NSMutableArray new];
    _entitlementsBlocks = [NSMutableArray new];
    _productsBlocks = [NSMutableArray new];
    _offeringsBlocks = [NSMutableArray new];
    _userInfoBlocks = [NSMutableArray new];
  }
  
  return self;
}

- (void)transferCachedPermissionsIfNeeded {
  BOOL alreadyTransfered = [self.persistentStorage loadBoolforKey:kKeyQPermissionsTransfered];
  if (!alreadyTransfered) {
    NSDictionary<NSString *, QONEntitlement *> *entitlements = [self.persistentStorage loadObjectForKey:kKeyQUserDefaultsPermissions];
    NSTimeInterval cachedPermissionsTimestamp = [self cachedPermissionsTimestamp];
    [self.persistentStorage storeObject:entitlements forKey:kKeyQUserDefaultsPermissions];
    [self.persistentStorage storeDouble:cachedPermissionsTimestamp forKey:kKeyQUserDefaultsPermissionsTimestamp];
    
    [self.persistentStorage storeBool:YES forKey:kKeyQPermissionsTransfered];
  }
}

- (void)supportMigrationFromOldVersions {
  [NSKeyedUnarchiver setClass:[QONLaunchResult class] forClassName:@"QNLaunchResult"];
  [NSKeyedUnarchiver setClass:[QONProduct class] forClassName:@"QNProduct"];
  [NSKeyedUnarchiver setClass:[QONOfferings class] forClassName:@"QNOfferings"];
  [NSKeyedUnarchiver setClass:[QONOffering class] forClassName:@"QNOffering"];
}

- (void)setEntitlementsCacheLifetime:(QONEntitlementsCacheLifetime)cacheLifetime {
  self.cacheLifetime = cacheLifetime;
}

- (void)storeLaunchResultIfNeeded:(QONLaunchResult *)launchResult {
  if (launchResult.timestamp > 0) {
    NSDate *currentDate = [NSDate date];
    [self storeEntitlements:launchResult.entitlements];
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

- (BOOL)isUserStable {
  return self.launchingFinished && !self.identityInProgress && self.pendingIdentityUserID.length == 0 && !self.unhandledLogoutAvailable;
}

- (void)launchWithCompletion:(nullable QONLaunchCompletionHandler)completion {
  __block __weak QNProductCenterManager *weakSelf = self;
  
  [self launch:^(QONLaunchResult * _Nonnull result, NSError * _Nullable error) {
    [weakSelf storeLaunchResultIfNeeded:result];
    
    weakSelf.launchResult = result;
    weakSelf.launchError = error;

    [weakSelf executeUserBlocks];
    
    NSArray *storeProducts = [weakSelf.storeKitService getLoadedProducts];
    if (!weakSelf.productsLoading && storeProducts.count == 0) {
      [weakSelf loadProducts];
    }

    [weakSelf handlePendingRequests:error];
    
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
  
  self.pendingIdentityUserID = userID;
  if (!self.launchingFinished || self.restoreInProgress) {
    return;
  }
  
  self.identityInProgress = YES;
  if (self.launchError) {
    __block __weak QNProductCenterManager *weakSelf = self;

    [weakSelf launch:^(QONLaunchResult * _Nullable result, NSError * _Nullable error) {
      if (error) {
        weakSelf.identityInProgress = NO;
        [weakSelf executeEntitlementsBlocksWithError:error];
        [weakSelf.remoteConfigManager userChangingRequestFailedWithError:error];
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
      [weakSelf executeEntitlementsBlocksWithError:error];
      [weakSelf.remoteConfigManager userChangingRequestFailedWithError:error];
      return;
    }
    
    weakSelf.pendingIdentityUserID = nil;
    
    [weakSelf.userInfoService storeCustomIdentityUserID:userID];
    
    if ([currentUserID isEqualToString:result]) {
      [weakSelf handlePendingRequests:nil];
    } else {
      [[QNAPIClient shared] setUserID:result];
      [weakSelf.remoteConfigManager userHasBeenChanged];
      
      [weakSelf resetActualPermissionsCache];
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
    [self.remoteConfigManager userHasBeenChanged];
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

- (void)userInfo:(QONUserInfoCompletionHandler)completion {
  if (!self.launchingFinished) {
    [self.userInfoBlocks addObject:completion];
    return;
  }
  
  [self actualizeUserInfo];
  completion(self.user, self.launchError);
}

- (void)presentCodeRedemptionSheet {
  [self.storeKitService presentCodeRedemptionSheet];
}

- (void)checkEntitlements:(QONEntitlementsCompletionHandler)completion {
  if (!completion) {
    return;
  }

  @synchronized (self) {
    [self.entitlementsBlocks addObject:completion];
    [self handlePendingRequests:nil];
  }
}

- (void)handleLogout {
  self.unhandledLogoutAvailable = NO;
  [self launchWithCompletion:nil];
}

- (void)purchaseProduct:(QONProduct *)product completion:(QONPurchaseCompletionHandler)completion {
  if (product.offeringID.length > 0) {
    QONOffering *offering = [self.launchResult.offerings offeringForIdentifier:product.offeringID];
    [self purchase:product.qonversionID offeringID:offering.identifier completion:completion];
  } else {
    [self purchase:product.qonversionID offeringID:nil completion:completion];
  }
}

- (void)purchase:(NSString *)productID completion:(QONPurchaseCompletionHandler)completion {
  [self purchase:productID offeringID:nil completion:completion];
}

- (void)purchase:(NSString *)productID offeringID:(NSString *)offeringID completion:(QONPurchaseCompletionHandler)completion {
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

- (void)prepareDelayedPurchase:(NSString *)productID offeringID:offeringID completion:(QONPurchaseCompletionHandler)completion {
  QONProductsCompletionHandler productsCompletion = ^(NSDictionary<NSString *, QONProduct *> *result, NSError  *_Nullable error) {
    if (error) {
      run_block_on_main(completion, @{}, error, NO);
      return;
    }
    
    [self processPurchase:productID offeringID:offeringID completion:completion];
  };
  
  [self.productsBlocks addObject:productsCompletion];
}

- (void)processPurchase:(NSString *)productID offeringID:(NSString *)offeringID completion:(QONPurchaseCompletionHandler)completion {
  QONProduct *product;
  if (offeringID.length > 0) {
    QONOffering *offering = [self.launchResult.offerings offeringForIdentifier:offeringID];
    
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
  
  [self processProductPurchase:product completion:completion];
}

- (void)processProductPurchase:(QONProduct *)product completion:(QONPurchaseCompletionHandler)completion {
  if (self.purchasingBlocks[product.storeID]) {
    QONVERSION_LOG(@"Purchasing in process");
    return;
  }
  
  if (product && [_storeKitService purchase:product.storeID]) {
    self.purchasingBlocks[product.storeID] = completion;
    
    return;
  }
  
  QONVERSION_LOG(@"❌ Store product with id: %@ not found", product.storeID);
  run_block_on_main(completion, @{}, [QONErrors errorWithQONErrorCode:QONErrorProductNotFound], NO);
}

- (void)restore:(QNRestoreCompletionHandler)completion {
  if (completion != nil) {
    [self.restorePurchasesBlocks addObject:completion];
  }

  if (self.restoreInProgress) {
    return;
  }

  self.awaitingRestoreResult = YES;
  self.restoreInProgress = YES;

  [self.storeKitService restore];
}

- (void)actualizeEntitlements:(QONEntitlementsCompletionHandler)completion {
  __block __weak QNProductCenterManager *weakSelf = self;

  [self launchWithCompletion:^(QONLaunchResult * _Nonnull result, NSError * _Nullable error) {
      weakSelf.unhandledLogoutAvailable = NO;
      NSDictionary<NSString *, QONEntitlement *> *entitlements = result.entitlements;
      NSError *resultError = error;
      if (error && !weakSelf.pendingIdentityUserID) {
        entitlements = [weakSelf getActualEntitlementsForDefaultState:NO];
        resultError = entitlements ? nil : error;
      }

      run_block_on_main(completion, entitlements, resultError);
  }];
}

- (void)prepareEntitlementsResultWithCompletion:(QONEntitlementsCompletionHandler)completion {
  if (self.launchError || self.unhandledLogoutAvailable) {
    [self actualizeEntitlements:completion];
    return;
  }

  NSDictionary<NSString *, QONEntitlement *> *entitlements = [self getActualEntitlementsForDefaultState:YES];
  entitlements = entitlements ?: @{};

  BOOL entitlementsAreActual = YES;
  NSDate *currentDate = [NSDate date];
  for (NSString *entitlementId in entitlements) {
    QONEntitlement *value = entitlements[entitlementId];
    if (value.isActive && value.expirationDate != nil && value.expirationDate.timeIntervalSince1970 < currentDate.timeIntervalSince1970) {
      entitlementsAreActual = NO;
      break;
    }
  }

  if (entitlementsAreActual) {
    run_block_on_main(completion, entitlements, nil);
  } else {
    [self actualizeEntitlements:completion];
  }
}

- (void)fireEntitlementsBlocks:(NSArray<QONEntitlementsCompletionHandler> *)blocks result:(NSDictionary<NSString *, QONEntitlement *> *)entitlements error:(NSError *)error {
  for (QONEntitlementsCompletionHandler block in blocks) {
    run_block_on_main(block, entitlements, error);
  }
}

- (void)executeEntitlementsBlocksWithError:(NSError *)error {
  @synchronized (self) {
    if (self.entitlementsBlocks.count == 0) {
      return;
    }
    
    NSMutableArray <QONEntitlementsCompletionHandler> *_blocks = [self.entitlementsBlocks copy];
    [self.entitlementsBlocks removeAllObjects];
    
    if (error) {
      if (self.pendingIdentityUserID.length > 0) {
        [self fireEntitlementsBlocks:[_blocks copy] result:@{} error:error];
      } else {
        NSDictionary<NSString *, QONEntitlement *> *cachedEntitlements = [self getActualEntitlementsForDefaultState:NO];
        cachedEntitlements = cachedEntitlements ?: @{};
        [self fireEntitlementsBlocks:[_blocks copy] result:cachedEntitlements error:error];
      }
    } else {
      [self prepareEntitlementsResultWithCompletion:^(NSDictionary<NSString *,QONEntitlement *> * _Nonnull result, NSError * _Nullable error) {
        [self fireEntitlementsBlocks:[_blocks copy] result:result ?: @{} error:error];
      }];
    }
  }
}

- (void)executeUserBlocks {
  @synchronized (self) {
    NSArray <QONUserInfoCompletionHandler> *blocks = [self.userInfoBlocks copy];
    if (blocks.count == 0) {
      return;
    }
    
    [self.userInfoBlocks removeAllObjects];
    
    [self actualizeUserInfo];
    for (QONUserInfoCompletionHandler block in blocks) {
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
    
    NSArray <QONOfferingsCompletionHandler> *blocks = [self.offeringsBlocks copy];
    
    [self.offeringsBlocks removeAllObjects];
    
    if (error) {
      for (QONOfferingsCompletionHandler block in blocks) {
        run_block_on_main(block, nil, error);
      }
      
      return;
    }
    
    NSError *resultError = error ?: _launchError;
    
    QONOfferings *offerings = [self enrichOfferingsWithStoreProducts];
    resultError = offerings ? nil : resultError;
    
    for (QONOfferingsCompletionHandler block in blocks) {
      run_block_on_main(block, offerings, resultError);
    }
  }
}

- (QONOfferings *)enrichOfferingsWithStoreProducts {
  QONOfferings *offerings = [self getActualOfferings];
  
  for (QONOffering *offering in offerings.availableOfferings) {
    for (QONProduct *product in offering.products) {
      QONProduct *qnProduct = [self productAt:product.qonversionID];
      
      product.skProduct = qnProduct.skProduct;
    }
  }
  
  return offerings;
  
}

- (void)executeProductsBlocks {
  [self executeProductsBlocksWithError:nil];
}

- (void)executeProductsBlocksWithError:(NSError * _Nullable)error {
  @synchronized (self) {
    NSArray <QONProductsCompletionHandler> *_blocks = [self->_productsBlocks copy];
    if (_blocks.count == 0) {
      return;
    }
    
    [_productsBlocks removeAllObjects];
    
    if (error) {
      for (QONProductsCompletionHandler _block in _blocks) {
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
    for (QONProductsCompletionHandler _block in _blocks) {
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

- (void)products:(QONProductsCompletionHandler)completion {
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

- (void)checkTrialIntroEligibilityForProductIds:(NSArray<NSString *> *)productIds completion:(QONEligibilityCompletionHandler)completion {
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

- (void)offerings:(QONOfferingsCompletionHandler)completion {
  @synchronized (self) {
    [self.offeringsBlocks addObject:completion];
    
    __block __weak QNProductCenterManager *weakSelf = self;
    QONProductsCompletionHandler productsCompletion = ^(NSDictionary<NSString *, QONProduct *> *result, NSError  *_Nullable error) {
      [weakSelf executeOfferingsBlocksWithError:error];
    };
    
    [self products:productsCompletion];
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
  _launchingFinished = NO;
  __block __weak QNProductCenterManager *weakSelf = self;
  [self.apiClient launchRequest:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
    @synchronized (weakSelf) {
      weakSelf.launchingFinished = YES;
      NSNotification *notification = [NSNotification notificationWithName:kLaunchIsFinishedNotification object:self];
      [[NSNotificationCenter defaultCenter] postNotification:notification];
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
    
    weakSelf.productsEntitlementsRelation = [QNMapper mapProductsEntitlementsRelation:result.data];
    [weakSelf.persistentStorage storeObject:weakSelf.productsEntitlementsRelation forKey:kKeyQUserDefaultsProductsPermissionsRelation];
    
    QONLaunchResult *launchResult = [QNMapper fillLaunchResult:result.data];
    completion(launchResult, nil);
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      [weakSelf.apiClient processStoredRequests];
    });
  }];
}

- (void)handleFailedTransaction:(SKPaymentTransaction *)transaction forProduct:(SKProduct *)product error:(NSError *)error {
  QONPurchaseCompletionHandler _purchasingBlock = _purchasingBlocks[product.productIdentifier];
  if (_purchasingBlock) {
    run_block_on_main(_purchasingBlock, @{}, error, error.code == QONErrorCancelled);
    @synchronized (self) {
      [_purchasingBlocks removeObjectForKey:product.productIdentifier];
    }
  }
}

- (void)handlePurchases:(NSArray<QONStoreKit2PurchaseModel *> *)purchasesInfo completion:(QONDefaultCompletionHandler)completion {
  __block __weak QNProductCenterManager *weakSelf = self;
  __block QONDefaultCompletionHandler resultCompletion = [completion copy];
  [self.storeKitService receipt:^(NSString * receipt) {
    for (QONStoreKit2PurchaseModel *purchaseModel in purchasesInfo) {
      __block NSURLRequest *request = [self.apiClient handlePurchase:purchaseModel receipt:receipt completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
        BOOL success = error == nil;
        if (error && [QNUtils shouldPurchaseRequestBeRetried:error]) {
          [weakSelf.apiClient storeRequestForRetry:request transactionId:purchaseModel.transactionId];
        } else {
          [weakSelf.apiClient removeStoredRequestForTransactionId:purchaseModel.transactionId];
        }
        
        if (resultCompletion) {
          resultCompletion(success, error);
          resultCompletion = nil;
        }
      }];
    }
  }];
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
  
  [self.storeKitService receipt:^(NSString * receipt) {
    __block NSURLRequest *request = [weakSelf.apiClient purchaseRequestWith:product transaction:transaction receipt:receipt completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
      QONPurchaseCompletionHandler _purchasingBlock = weakSelf.purchasingBlocks[product.productIdentifier];
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
          //
          if (!resultError) {
            [weakSelf handleRestoreResult:launchResult.entitlements error:nil];
          }
        } else {
          NSDictionary<NSString *, QONEntitlement *> *resultEntitlements = launchResult.entitlements;
          if (resultError) {
            if ([self shouldCalculateEntitlementsForError:error]) {
              resultEntitlements = [self calculateEntitlementsForTransactions:@[transaction] products:@[product]];
              [weakSelf.purchasesDelegate didReceiveUpdatedEntitlements:resultEntitlements];
            }
          } else {
            [weakSelf.purchasesDelegate didReceiveUpdatedEntitlements:resultEntitlements];
          }
        }
      }
    }];
  }];
}

- (BOOL)shouldCalculateEntitlementsForError:(NSError *)error {
  return (error.code >= kInternalServerErrorFirstCode && error.code <= kInternalServerErrorLastCode) || [QNUtils isConnectionError:error];
}

- (void)handleRestoreResult:(NSDictionary<NSString *, QONEntitlement *> *)entitlements error:(NSError *)error {
  if (!self.awaitingRestoreResult) {
    return;
  }
  self.awaitingRestoreResult = NO;
  
  self.restoredTransactions = nil;
  
  [self executeRestoreBlocksWithResult:entitlements error:error];
}

- (void)handleRestoreCompletedTransactionsFinished {
  if (!self.awaitingRestoreResult) {
    return;
  }
  self.awaitingRestoreResult = NO;

  NSArray *restoredTransactionsCopy = [self.restoredTransactions copy];
  self.restoredTransactions = nil;
  __block __weak QNProductCenterManager *weakSelf = self;
  [self launch:^(QONLaunchResult * _Nonnull result, NSError * _Nullable error) {
    if (error) {
      if ([weakSelf shouldCalculateEntitlementsForError:error]) {
        NSArray<SKProduct *> *storeProducts = [weakSelf.storeKitService getLoadedProducts];
        NSDictionary<NSString *, QONEntitlement *> *calculatedEntitlements = [weakSelf calculateEntitlementsForRestoredTransactions:restoredTransactionsCopy products:storeProducts];

        [weakSelf executeRestoreBlocksWithResult:calculatedEntitlements error:nil];
      } else {
        [weakSelf executeRestoreBlocksWithResult:@{} error:error];
      }
    } else if (result) {
      [weakSelf storeLaunchResultIfNeeded:result];
      weakSelf.launchResult = result;
      [weakSelf executeRestoreBlocksWithResult:result.entitlements error:error];
    }
  }];
}

- (void)handleRestoreCompletedTransactionsFailed:(NSError *)error {
  self.awaitingRestoreResult = NO;
  [self executeRestoreBlocksWithResult:@{} error:error];
}

- (void)executeRestoreBlocksWithResult:(NSDictionary<NSString *, QONEntitlement *> *)entitlements error:(NSError *)error {
  self.restoreInProgress = NO;

  NSMutableArray <QONEntitlementsCompletionHandler> *_blocks = [self.restorePurchasesBlocks copy];
  [self.restorePurchasesBlocks removeAllObjects];

  for (QONEntitlementsCompletionHandler block in _blocks) {
    run_block_on_main(block, entitlements, error);
  }

  [self handlePendingRequests:error];
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
    [self.promoPurchasesDelegate shouldPurchasePromoProductWithIdentifier:product.productIdentifier executionBlock:^(QONPurchaseCompletionHandler _Nonnull completion) {
      weakSelf.purchasingBlocks[product.productIdentifier] = completion;
      
      [weakSelf.storeKitService purchaseProduct:product];
    }];
    
    return NO;
  }
  
  return YES;
}

- (void)storeEntitlements:(NSDictionary<NSString *, QONEntitlement *> *)entitlements {
  self.entitlements = entitlements;
  NSDate *currentDate = [NSDate date];
  
  [self.persistentStorage storeDouble:currentDate.timeIntervalSince1970 forKey:kKeyQUserDefaultsPermissionsTimestamp];
  [self.persistentStorage storeObject:entitlements forKey:kKeyQUserDefaultsPermissions];
}

- (NSDictionary<NSString *, QONEntitlement *> * _Nullable)getActualEntitlementsForDefaultState:(BOOL)defaultState {
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
                  completion:(QONPurchaseCompletionHandler)completion {
  if (error) {
    if ([self shouldCalculateEntitlementsForError:error]) {
      NSDictionary<NSString *, QONEntitlement *> *calculatedEntitlements = [self calculateEntitlementsForTransactions:@[transaction] products:@[product]];
      run_block_on_main(completion, calculatedEntitlements, nil, cancelled);
    } else {
      run_block_on_main(completion, @{}, error, cancelled);
    }
  } else {
    run_block_on_main(completion, result, nil, cancelled);
  }
}

- (NSDictionary<NSString *, QONEntitlement *> *)calculateEntitlementsForRestoredTransactions:(NSArray<SKPaymentTransaction *> *)transactions
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

  return [self calculateEntitlementsForTransactions:resultTransactionsDict.allValues products:products];
}

- (NSDictionary<NSString *, QONEntitlement *> *)calculateEntitlementsForTransactions:(NSArray<SKPaymentTransaction *> *)transactions
                                                                            products:(NSArray<SKProduct *> *)products {
  NSMutableDictionary<NSString *, QONEntitlement *> *resultEntitlements = [NSMutableDictionary new];
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
        NSDictionary<NSString *, QONEntitlement *> *entitlements = [self createEntitlementsForProductsMap:qonversionProductsMap transaction:transaction expirationDate:expirationDate];

        [resultEntitlements addEntriesFromDictionary:entitlements];
      }
    }
  } else {
    for (SKPaymentTransaction *transaction in transactions) {
      QONProduct *qonversionProduct = qonversionProductsMap[transaction.payment.productIdentifier];
      NSDate *expirationDate = [QNUtils calculateExpirationDateForProduct:qonversionProduct fromDate:transaction.transactionDate];
      if (!expirationDate || [expirationDate compare:[NSDate date]] == NSOrderedDescending) {
        NSDictionary<NSString *, QONEntitlement *> *entitlements = [self createEntitlementsForProductsMap:qonversionProductsMap transaction:transaction expirationDate:expirationDate];

        [resultEntitlements addEntriesFromDictionary:entitlements];
      }
    }
  }

  resultEntitlements = [self mergeEntitlements:resultEntitlements];
  
  NSDictionary<NSString *, QONEntitlement *> *resultEntitlementsCopy = [resultEntitlements copy];

  [self storeEntitlements:resultEntitlementsCopy];

  return resultEntitlementsCopy;
}

- (NSMutableDictionary<NSString *, QONEntitlement *> *)mergeEntitlements:(NSMutableDictionary *)entitlements {
  NSDictionary *currentEntitlements = [self getActualEntitlementsForDefaultState:NO];
  NSMutableDictionary<NSString *, QONEntitlement *> *resultEntitlements = currentEntitlements ? [currentEntitlements mutableCopy] : [NSMutableDictionary new];

  for (QONEntitlement *entitlement in entitlements.allValues) {
    QONEntitlement *currentEntitlement = resultEntitlements[entitlement.entitlementID];
    if (!currentEntitlement || !currentEntitlement.isActive || [entitlement.expirationDate compare:currentEntitlement.expirationDate] == NSOrderedDescending) {
      resultEntitlements[entitlement.entitlementID] = entitlement;
    }
  }

  return resultEntitlements;
}

- (NSDictionary<NSString *, QONEntitlement *> *)createEntitlementsForProductsMap:(NSDictionary *)productsMap
                                                                     transaction:(SKPaymentTransaction *)transaction
                                                                  expirationDate:(NSDate *)expirationDate {
  NSMutableDictionary<NSString *, QONEntitlement *> *resultEntitlements = [NSMutableDictionary new];

  QONProduct *qonversionProduct = productsMap[transaction.payment.productIdentifier];

  NSArray<NSString *> *entitlementsIds = self.productsEntitlementsRelation[qonversionProduct.qonversionID];
  for (NSString *entitlementId in entitlementsIds) {
    QONEntitlement *entitlement = [self createEntitlementsForId:entitlementId qonversionProduct:qonversionProduct transaction:transaction expirationDate:expirationDate];

    resultEntitlements[entitlement.entitlementID] = entitlement;
  }

  return [resultEntitlements copy];
}

- (QONEntitlement *)createEntitlementsForId:(NSString *)entitlementId
                       qonversionProduct:(QONProduct *)qonversionProduct
                             transaction:(SKPaymentTransaction *)transaction
                          expirationDate:(NSDate *)expirationDate {
  QONEntitlement *entitlement = [[QONEntitlement alloc] init];
  entitlement.entitlementID = entitlementId;
  entitlement.isActive = YES;
  entitlement.renewState = QONEntitlementRenewStateUnknown;
  entitlement.source = QONEntitlementSourceAppStore;
  entitlement.productID = qonversionProduct.qonversionID;
  entitlement.startedDate = transaction.transactionDate;
  entitlement.expirationDate = expirationDate;

  return entitlement;
}

- (void)actualizeUserInfo {
  NSString *qonversionId = [self.userInfoService obtainUserID];
  NSString *identityId = [self.userInfoService obtainCustomIdentityUserID];

  QONUser *actualUser = [[QONUser alloc] initWithID:qonversionId originalAppVersion:self.user.originalAppVersion identityId:identityId ];
  
  self.user = actualUser;
}

- (void)handlePendingRequests:(NSError *)lastError {
  if (!self.launchingFinished || self.restoreInProgress || self.identityInProgress) {
    return;
  }

  if (self.pendingIdentityUserID) {
    [self identify:self.pendingIdentityUserID];
  } else if (self.unhandledLogoutAvailable) {
    [self handleLogout];
  } else {
    [self.remoteConfigManager handlePendingRequests];
    [self executeEntitlementsBlocksWithError:lastError];
  }
}

@end
