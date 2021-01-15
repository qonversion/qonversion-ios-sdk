#import "QNProductCenterManager.h"
#import "QNInMemoryStorage.h"
#import "QNUserDefaultsStorage.h"
#import "QNStoreKitService.h"
#import "QNAPIClient.h"
#import "QNMapper.h"
#import "QNLaunchResult.h"
#import "QNMapperObject.h"
#import "QNKeeper.h"
#import "QNProduct.h"
#import "QNErrors.h"
#import "QNPromoPurchasesDelegate.h"
#import "QNOfferings.h"
#import "QNOffering.h"
#import "QNIntroEligibility.h"

static NSString * const kLaunchResult = @"qonversion.launch.result";
static NSString * const kUserDefaultsSuiteName = @"qonversion.product-center.suite";

@interface QNProductCenterManager() <QNStoreKitServiceDelegate>

@property (nonatomic, weak) id<QNPromoPurchasesDelegate> promoPurchasesDelegate;

@property (nonatomic) QNStoreKitService *storeKitService;
@property (nonatomic) QNUserDefaultsStorage *persistentStorage;

@property (nonatomic, copy) QNRestoreCompletionHandler restorePurchasesBlock;

@property (nonatomic, strong) NSMutableDictionary <NSString *, QNPurchaseCompletionHandler> *purchasingBlocks;
@property (nonatomic, strong) NSMutableArray<QNPermissionCompletionHandler> *permissionsBlocks;
@property (nonatomic, strong) NSMutableArray<QNProductsCompletionHandler> *productsBlocks;
@property (nonatomic, strong) NSMutableArray<QNOfferingsCompletionHandler> *offeringsBlocks;
@property (nonatomic, strong) NSMutableArray<QNExperimentsCompletionHandler> *experimentsBlocks;
@property (nonatomic) QNAPIClient *apiClient;

@property (nonatomic) QNLaunchResult *launchResult;
@property (nonatomic) NSError *launchError;

@property (nonatomic, assign) BOOL launchingFinished;
@property (nonatomic, assign) BOOL productsLoading;

@end

@implementation QNProductCenterManager

- (instancetype)init {
  self = super.init;
  if (self) {
    _launchingFinished = NO;
    _productsLoading = NO;
    _launchError = nil;
    _launchResult = nil;
    
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

- (QNLaunchResult *)launchModel {
  return [self.persistentStorage loadObjectForKey:kLaunchResult];
}

- (void)launchWithCompletion:(QNLaunchCompletionHandler)completion {
  _launchingFinished = NO;
  
  __block __weak QNProductCenterManager *weakSelf = self;
  
  [self launch:^(QNLaunchResult * _Nonnull result, NSError * _Nullable error) {
    if (result) {
      [weakSelf.persistentStorage storeObject:result forKey:kLaunchResult];
    }
    
    weakSelf.launchResult = result;
    weakSelf.launchError = error;
    
    [weakSelf executePermissionBlocks];
    [weakSelf executeExperimentsBlocks];
    
    NSArray *storeProducts = [weakSelf.storeKitService getLoadedProducts];
    if (!weakSelf.productsLoading && storeProducts.count == 0) {
      [weakSelf loadProducts];
    }
    
    if (result.uid) {
      QNKeeper.userID = result.uid;
      [[QNAPIClient shared] setUserID:result.uid];
    }
    
    if (completion) {
      run_block_on_main(completion, result, error)
    }
    
    if (error) {
      QONVERSION_LOG(@"❗️ Request failed %@", error.description);
    }
  }];
}

- (void)setPromoPurchasesDelegate:(id<QNPromoPurchasesDelegate>)delegate {
  _promoPurchasesDelegate = delegate;
}

- (void)checkPermissions:(QNPermissionCompletionHandler)completion {
  if (!completion) {
    return;
  }
  
  @synchronized (self) {
    if (!_launchingFinished) {
      [self.permissionsBlocks addObject:completion];
      return;
    }
  }
  
  run_block_on_main(completion, self.launchResult.permissions, self.launchError);
}

- (void)purchase:(NSString *)productID completion:(QNPurchaseCompletionHandler)completion {
  @synchronized (self) {
    NSArray *storeProducts = [self.storeKitService getLoadedProducts];
    
    if (self.launchError) {
      __block __weak QNProductCenterManager *weakSelf = self;
      [self launchWithCompletion:^(QNLaunchResult * _Nonnull result, NSError * _Nullable error) {
        if (error) {
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
    QONVERSION_LOG([NSString stringWithFormat:@"❌ product with id: %@ not found", product.qonversionID]);
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
  
  QONVERSION_LOG([NSString stringWithFormat:@"❌ product with id: %@ not found", product.qonversionID]);
  run_block_on_main(completion, @{}, [QNErrors errorWithQNErrorCode:QNErrorProductNotFound], NO);
}

- (void)restoreWithCompletion:(QNRestoreCompletionHandler)completion {
  self.restorePurchasesBlock = completion;
  [self.storeKitService restore];
}

- (void)executePermissionBlocks {
  @synchronized (self) {
    NSMutableArray <QNPermissionCompletionHandler> *_blocks = [self->_permissionsBlocks copy];
    if (!_blocks) {
      return;
    }
    
    [self->_permissionsBlocks removeAllObjects];

    for (QNPermissionCompletionHandler block in _blocks) {
      run_block_on_main(block, self.launchResult.permissions ?: @{}, self.launchError);
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
    NSArray <QNOfferingsCompletionHandler> *blocks = [self.offeringsBlocks copy];
    if (blocks.count == 0) {
      return;
    }
    
    [self.offeringsBlocks removeAllObjects];
    
    NSError *resultError = error ?: _launchError;
    QNOfferings *offerings = nil;
    
    if (!resultError) {
      offerings = [self enrichOfferingsWithStoreProducts];
    }
    
    for (QNOfferingsCompletionHandler block in blocks) {
      run_block_on_main(block, offerings, resultError);
    }
  }
}

- (QNOfferings *)enrichOfferingsWithStoreProducts {
  for (QNOffering *offering in self.launchResult.offerings.availableOfferings) {
    for (QNProduct *product in offering.products) {
      QNProduct *qnProduct = [self productAt:product.qonversionID];
      
      product.skProduct = qnProduct.skProduct;
    }
  }
  
  return self.launchResult.offerings;
  
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
    NSArray *products = [(_launchResult.products ?: @{}) allValues];;
    
    NSDictionary *resultProducts = [self enrichProductsWithStoreProducts:products];
    NSError *resultError = error ?: _launchError;
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
  
  NSArray<QNProduct *> *products = [_launchResult.products allValues];
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
        QONVERSION_LOG([NSString stringWithFormat:@"❌ product with id: %@ not found", product.qonversionID]);
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
      NSMutableDictionary<NSString *, QNProduct *> *resultEligibility = [NSMutableDictionary new];
      
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
    if (!self.launchingFinished) {
      [self.experimentsBlocks addObject:completion];
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
  NSDictionary *products = _launchResult.products ?: @{};
  
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
    
    QNLaunchResult *launchResult = [QNMapper fillLaunchResult:result.data];
    completion(launchResult, nil);
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      [weakSelf.apiClient processStoredRequests];
    });
  }];
}

- (void)process:(NSDictionary * _Nullable)dict error:(NSError *)error
     completion:(void (^)(QNLaunchResult * _Nullable result, NSError * _Nullable error))completion {
  
  @synchronized (self) {
    self->_launchingFinished = YES;
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
  
  QNLaunchResult *launchResult = [QNMapper fillLaunchResult:result.data];
  completion(launchResult, nil);
}

// MARK: - QNStoreKitServiceDelegate

- (void)handlePurchasedTransaction:(SKPaymentTransaction *)transaction forProduct:(SKProduct *)product {
  __block __weak QNProductCenterManager *weakSelf = self;
  
  [self.storeKitService receipt:^(NSString * receipt) {
    [weakSelf.apiClient purchaseRequestWith:product transaction:transaction receipt:receipt completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
      QNPurchaseCompletionHandler _purchasingBlock = weakSelf.purchasingBlocks[product.productIdentifier];
      [[weakSelf storeKitService] finishTransaction:transaction];
      @synchronized (weakSelf) {
        [weakSelf.purchasingBlocks removeObjectForKey:product.productIdentifier];
      }
      
      if (error) {
        run_block_on_main(_purchasingBlock, @{}, error, NO);
        return;
      }
      
      QNMapperObject *result = [QNMapper mapperObjectFrom:dict];
      if (result.error) {
        run_block_on_main(_purchasingBlock, @{}, result.error, NO);
        return;
      }
      
      QNLaunchResult *launchResult = [QNMapper fillLaunchResult:result.data];
      @synchronized (weakSelf) {
        [weakSelf.launchResult setPermissions:launchResult.permissions];
      }
      if (_purchasingBlock) {
        run_block_on_main(_purchasingBlock, launchResult.permissions, error, NO);
      }
    }];
  }];
  
}

- (void)handleRestoreCompletedTransactionsFinished {
  if (self.restorePurchasesBlock) {
    [self launch:^(QNLaunchResult * _Nonnull result, NSError * _Nullable error) {
      QNRestoreCompletionHandler restorePurchasesBlock = [self.restorePurchasesBlock copy];
      self.restorePurchasesBlock = nil;
      if (result) {
        run_block_on_main(restorePurchasesBlock, result.permissions, error);
      } else if (error) {
        run_block_on_main(restorePurchasesBlock, @{}, error);
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

- (void)handleFailedTransaction:(SKPaymentTransaction *)transaction forProduct:(SKProduct *)product {
  NSError *error = [QNErrors errorFromTransactionError:transaction.error];
  
  QNPurchaseCompletionHandler _purchasingBlock = _purchasingBlocks[product.productIdentifier];
  if (_purchasingBlock) {
    run_block_on_main(_purchasingBlock, @{}, error, error.code == QNErrorCancelled);
    @synchronized (self) {
      [_purchasingBlocks removeObjectForKey:product.productIdentifier];
    }
  }
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
