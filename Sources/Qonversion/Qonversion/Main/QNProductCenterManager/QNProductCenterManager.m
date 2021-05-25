#import "QNProductCenterManager.h"
#import "QNInMemoryStorage.h"
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
@property (nonatomic, strong) NSMutableArray<QNPermissionCompletionHandler> *permissionsBlocks;
@property (nonatomic, strong) NSMutableArray<QNProductsCompletionHandler> *productsBlocks;
@property (nonatomic, strong) NSMutableArray<QNOfferingsCompletionHandler> *offeringsBlocks;
@property (nonatomic, strong) NSMutableArray<QNExperimentsCompletionHandler> *experimentsBlocks;
@property (nonatomic) QNAPIClient *apiClient;

@property (nonatomic, strong) QNLaunchResult *launchResult;
@property (nonatomic, strong) NSError *launchError;

@property (nonatomic, assign) BOOL launchingFinished;
@property (nonatomic, assign) BOOL productsLoading;
@property (nonatomic, assign) BOOL forceLaunchRetry;
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
    _forceLaunchRetry = NO;
    _launchError = nil;
    _launchResult = nil;
    
    QNServicesAssembly *servicesAssembly = [QNServicesAssembly new];
    
    _userInfoService = [servicesAssembly userInfoService];
    _identityManager = [servicesAssembly identityManager];
    
    _apiClient = [QNAPIClient shared];
    _storeKitService = [[QNStoreKitService alloc] initWithDelegate:self];
    
    _persistentStorage = [[QNUserDefaultsStorage alloc] init];
    [_persistentStorage setUserDefaults:[[NSUserDefaults alloc] initWithSuiteName:kUserDefaultsSuiteName]];
    
    _purchasingBlocks = [NSMutableDictionary new];
    _permissionsBlocks = [NSMutableArray new];
    _productsBlocks = [NSMutableArray new];
    _offeringsBlocks = [NSMutableArray new];
    _experimentsBlocks = [NSMutableArray new];
  }
  
  return self;
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
  NSTimeInterval cachedLaunchResultTimeStamp = [self cachedLaunchResultTimeStamp];
  BOOL isCacheOutdated = [QNUtils isCacheOutdated:cachedLaunchResultTimeStamp];
  
  return isCacheOutdated ? nil : result;
}

- (NSTimeInterval)cachedLaunchResultTimeStamp {
  return [self.persistentStorage loadDoubleForKey:kLaunchResultTimeStamp];
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

- (void)launchWithCompletion:(nullable QNLaunchCompletionHandler)completion {
  _launchingFinished = NO;
  
  __block __weak QNProductCenterManager *weakSelf = self;
  
  [self launch:^(QNLaunchResult * _Nonnull result, NSError * _Nullable error) {
    [weakSelf storeLaunchResultIfNeeded:result];
    
    weakSelf.launchResult = result;
    weakSelf.launchError = error;

    [weakSelf executeExperimentsBlocks];
    
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
  if (!self.launchingFinished) {
    self.pendingIdentityUserID = userID;
    
    return;
  }
  
  self.identityInProgress = YES;
  if (self.launchError) {
    __block __weak QNProductCenterManager *weakSelf = self;

    [weakSelf launch:^(QNLaunchResult * _Nullable result, NSError * _Nullable error) {
      weakSelf.identityInProgress = NO;
      
      if (error) {
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
  __block __weak QNProductCenterManager *weakSelf = self;
  [self.identityManager identify:userID completion:^(NSString *result, NSError * _Nullable error) {
    weakSelf.pendingIdentityUserID = nil;
    weakSelf.identityInProgress = NO;
    
    if (error) {
      [weakSelf executePermissionBlocksWithError:error];
    } else {
      [[QNAPIClient shared] setUserID:result];
      
      [weakSelf launchWithCompletion:nil];
    }
  }];
}

- (void)logout {
  [self.identityManager logout];
  
  NSString *userID = [self.userInfoService obtainUserID];
  [[QNAPIClient shared] setUserID:userID];
  
  self.unhandledLogoutAvailable = YES;
}

- (void)setPromoPurchasesDelegate:(id<QNPromoPurchasesDelegate>)delegate {
  _promoPurchasesDelegate = delegate;
}

- (void)setPurchasesDelegate:(id<QNPurchasesDelegate>)delegate {
  _purchasesDelegate = delegate;
}

- (void)userInfo:(QNUserInfoCompletionHandler)completion {
  [self.userInfoService obtainUserInfo:completion];
}

- (void)presentCodeRedemptionSheet {
  [self.storeKitService presentCodeRedemptionSheet];
}

- (void)checkPermissions:(QNPermissionCompletionHandler)completion {
  if (!completion) {
    return;
  }
  
  @synchronized (self) {
    if (!_launchingFinished || _identityInProgress) {
      [self.permissionsBlocks addObject:completion];
      return;
    }
    
    if (_pendingIdentityUserID) {
      [self.permissionsBlocks addObject:completion];
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

- (void)purchase:(NSString *)productID completion:(QNPurchaseCompletionHandler)completion {
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
          [weakSelf preparDelayedPurchase:productID completion:completion];
        } else {
          [weakSelf processPurchase:productID completion:completion];
        }
      }];
    } else if (!self.productsLoading && storeProducts.count == 0) {
      [self preparDelayedPurchase:productID completion:completion];
      
      [self loadProducts];
    } else {
      [self processPurchase:productID completion:completion];
    }
  }
}

- (void)preparDelayedPurchase:(NSString *)productID completion:(QNPurchaseCompletionHandler)completion {
  QNProductsCompletionHandler productsCompletion = ^(NSDictionary<NSString *, QNProduct *> *result, NSError  *_Nullable error) {
    if (error) {
      run_block_on_main(completion, @{}, error, NO);
      return;
    }
    
    [self processPurchase:productID completion:completion];
  };
  
  [self.productsBlocks addObject:productsCompletion];
}

- (void)processPurchase:(NSString *)productID completion:(QNPurchaseCompletionHandler)completion {
  QNProduct *product = [self QNProduct:productID];
  if (!product) {
    QONVERSION_LOG(@"❌ product with id: %@ not found", productID);
    run_block_on_main(completion, @{}, [QNErrors errorWithQNErrorCode:QNErrorProductNotFound], NO);
    return;
  }
  
  if (self.purchasingBlocks[product.storeID]) {
    QONVERSION_LOG(@"Purchasing in process");
    return;
  }
  
  if (product && [_storeKitService purchase:product.storeID]) {
    self.purchasingBlocks[product.storeID] = completion;
    return;
  }
  
  QONVERSION_LOG(@"❌ product with id: %@ not found", productID);
  run_block_on_main(completion, @{}, [QNErrors errorWithQNErrorCode:QNErrorProductNotFound], NO);
}

- (void)restoreWithCompletion:(QNRestoreCompletionHandler)completion {
  self.restorePurchasesBlock = completion;
  [self.storeKitService restore];
}

- (void)preparePermissionsResultWithCompletion:(QNPermissionCompletionHandler)completion {
  __block __weak QNProductCenterManager *weakSelf = self;
  
  if (self.launchError || self.unhandledLogoutAvailable) {
    [self launchWithCompletion:^(QNLaunchResult * _Nonnull result, NSError * _Nullable error) {
      weakSelf.unhandledLogoutAvailable = NO;
      QNLaunchResult *launchResult = result;
      NSError *resultError = error;
      if (error && !weakSelf.forceLaunchRetry && !weakSelf.pendingIdentityUserID) {
        QNLaunchResult *cachedLaunchResult = [weakSelf actualCachedLaunchResult];
        launchResult = cachedLaunchResult ?: launchResult;
        resultError = cachedLaunchResult ? nil : error;
      }
      
      run_block_on_main(completion, launchResult.permissions, resultError);
    }];
  } else {
    run_block_on_main(completion, self.launchResult.permissions, nil);
  }
}

- (void)executePermissionBlocks {
  [self executePermissionBlocksWithError:nil];
}

- (void)executePermissionBlocksWithError:(NSError *)error {
  @synchronized (self) {
    if (self.permissionsBlocks.count == 0) {
      return;
    }
    
    NSMutableArray <QNPermissionCompletionHandler> *_blocks = [self.permissionsBlocks copy];
    [self.permissionsBlocks removeAllObjects];
    
    if (error) {
      for (QNPermissionCompletionHandler block in _blocks) {
        run_block_on_main(block, @{}, error);
      }
    } else {
      [self preparePermissionsResultWithCompletion:^(NSDictionary<NSString *,QNPermission *> * _Nonnull result, NSError * _Nullable error) {
        for (QNPermissionCompletionHandler block in _blocks) {
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
  for (QNOffering *offering in offerings.availableOfferings) {
    for (QNProduct *product in offering.products) {
      QNProduct *qnProduct = [self productAt:product.qonversionID];
      
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
    
    weakSelf.forceLaunchRetry = NO;
    
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

- (void)handlePurchasedTransaction:(SKPaymentTransaction *)transaction forProduct:(SKProduct *)product {
  __block __weak QNProductCenterManager *weakSelf = self;
  
  [self.storeKitService receipt:^(NSString * receipt) {
    [weakSelf.apiClient purchaseRequestWith:product transaction:transaction receipt:receipt completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
      [weakSelf.storeKitService finishTransaction:transaction];
      
      QNPurchaseCompletionHandler _purchasingBlock = weakSelf.purchasingBlocks[product.productIdentifier];
      @synchronized (weakSelf) {
        [weakSelf.purchasingBlocks removeObjectForKey:product.productIdentifier];
      }
      
      if (error) {
        weakSelf.forceLaunchRetry = YES;
        run_block_on_main(_purchasingBlock, @{}, error, NO);
        return;
      }
      
      QNMapperObject *result = [QNMapper mapperObjectFrom:dict];
      if (result.error) {
        weakSelf.forceLaunchRetry = YES;
        run_block_on_main(_purchasingBlock, @{}, result.error, NO);
        return;
      }
      
      QNLaunchResult *launchResult = [QNMapper fillLaunchResult:result.data];
      @synchronized (weakSelf) {
        weakSelf.forceLaunchRetry = NO;
        weakSelf.launchResult = launchResult;
        weakSelf.launchError = nil;
      }
      
      [weakSelf storeLaunchResultIfNeeded:launchResult];
      
      if (_purchasingBlock) {
        run_block_on_main(_purchasingBlock, launchResult.permissions, error, NO);
      } else {
        if (transaction.transactionState != SKPaymentTransactionStateRestored) {
          [weakSelf.purchasesDelegate qonversionDidReceiveUpdatedPermissions:launchResult.permissions];
        }
      }
    }];
  }];
}

- (void)handleRestoreCompletedTransactionsFinished {
  if (self.restorePurchasesBlock) {
    __block __weak QNProductCenterManager *weakSelf = self;
    [self launch:^(QNLaunchResult * _Nonnull result, NSError * _Nullable error) {
      QNRestoreCompletionHandler restorePurchasesBlock = [weakSelf.restorePurchasesBlock copy];
      weakSelf.restorePurchasesBlock = nil;
      if (error) {
        weakSelf.forceLaunchRetry = YES;
        run_block_on_main(restorePurchasesBlock, @{}, error);
      } else if (result) {
        [weakSelf storeLaunchResultIfNeeded:result];
        weakSelf.launchResult = result;
        run_block_on_main(restorePurchasesBlock, result.permissions, error);
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
