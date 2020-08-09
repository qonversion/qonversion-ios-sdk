#import "QNProductCenterManager.h"
#import "QNInMemoryStorage.h"
#import "QNUserDefaultsStorage.h"
#import "QNStoreKitService.h"
#import "QNAPIClient.h"
#import "QNMapper.h"
#import "QNLaunchResult.h"
#import "QNMapperObject.h"
#import "QNKeeper.h"
#import "QNProduct+Protected.h"
#import "QNErrors.h"

static NSString * const kLaunchResult = @"qonversion.launch.result";
static NSString * const kUserDefaultsSuiteName = @"qonversion.product-center.suite";

@interface QNProductCenterManager() <QNStoreKitServiceDelegate>
 
@property (nonatomic) QNStoreKitService *storeKitService;
@property (nonatomic) QNUserDefaultsStorage *persistentStorage;

@property (nonatomic) NSMutableDictionary <NSString *, QNPurchaseCompletionHandler> *purchasingBlocks;

@property (nonatomic, copy) NSMutableArray *permissionsBlocks;
@property (nonatomic, copy) NSMutableArray *productsBlocks;
@property (nonatomic) QNAPIClient *apiClient;

@property (nonatomic) QNLaunchResult *launchResult;
@property (nonatomic) NSError *launchError;

@property (nonatomic, assign) BOOL launchingFinished;
@property (nonatomic, assign) BOOL productsLoaded;

@end

@implementation QNProductCenterManager

- (instancetype)init {
  self = super.init;
  if (self) {
    _launchingFinished = NO;
    _productsLoaded = NO;
    _launchError = nil;
    _launchResult = nil;
    
    _apiClient = [QNAPIClient shared];
    _storeKitService = [[QNStoreKitService alloc] initWithDelegate:self];
    
    _persistentStorage = [[QNUserDefaultsStorage alloc] init];
    [_persistentStorage setUserDefaults:[[NSUserDefaults alloc] initWithSuiteName:kUserDefaultsSuiteName]];
    
    _permissionsBlocks = [[NSMutableArray alloc] init];
    _productsBlocks = [[NSMutableArray alloc] init];
    _purchasingBlocks = [[NSMutableDictionary alloc] init];
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
    [weakSelf loadProducts];
    
    if (result.uid) {
      QNKeeper.userID = result.uid;
      [[QNAPIClient shared] setUserID:result.uid];
    }
    run_block_on_main(completion, result, error)
  }];
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
    QNProduct *product = [self QNProduct:productID];
    if (!product) {
      run_block_on_main(completion, nil, [QNErrors errorWithQNErrorCode:QNErrorProductNotFound], NO);
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
    
    run_block_on_main(completion, nil, [QNErrors errorWithQNErrorCode:QNErrorProductNotFound], NO);
  }
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

- (void)executeProductsBlocks {
  @synchronized (self) {
    NSMutableArray <QNProductsCompletionHandler> *_blocks = [self->_productsBlocks copy];
    if (_blocks.count == 0) {
      return;
    }
    
    [_productsBlocks removeAllObjects];
    NSDictionary *products = [(_launchResult.products ?: @{}) allValues];;
    NSMutableArray *resultProducts = [[NSMutableDictionary alloc] init];
    for (QNProduct *_product in products) {
      if (!_product.qonversionID) {
        continue;
      }
      
      QNProduct *qnProduct = [self productAt:_product.qonversionID];
      if (qnProduct) {
        [resultProducts setValue:qnProduct forKey:_product.qonversionID];
      }
    }
    
    for (QNProductsCompletionHandler _block in _blocks) {
      run_block_on_main(_block, resultProducts);
    }
    
  }
}

- (void)loadProducts {
  if (!_launchResult) {
    return;
  }
  
  NSArray<QNProduct *> *products = [_launchResult.products allValues];
  NSMutableSet *productsSet = [[NSMutableSet alloc] init];
  
  if (products) {
    for (QNProduct *product in products) {
      [productsSet addObject:product.storeID];
    }
  }

  [_storeKitService loadProducts:productsSet];
}

- (void)products:(QNProductsCompletionHandler)completion {
  @synchronized (self) {
    [self.productsBlocks addObject:completion];
    
    if (_productsLoaded) {
      [self executeProductsBlocks];
    }
    
    if (_launchingFinished && !_productsLoaded) {
      [self launchWithCompletion:nil];
    }
  }
}

- (void)handleProducts:(NSArray<SKProduct *> *)products {
  @synchronized (self) {
    self->_productsLoaded = YES;
  }
  
  [self executeProductsBlocks];
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

- (QNProduct * _Nullable)QNProductAtStoreID:(NSString *)productID {
  NSDictionary *products = _launchResult.products ?: @{};
  NSArray *productsList = [products allValues];
  
  if (productsList && productsList.count == 0) {
    return nil;
  }
  
  for (QNProduct *product in productsList) {
    if ([product.storeID isEqualToString:productID]) {
      return product;
    }
  }
  
  return nil;
}

- (QNProduct * _Nullable)QNProduct:(NSString *)productID {
  NSDictionary *products = _launchResult.products ?: @{};
  
  return products[productID];
}

- (void)launch:(void (^)(QNLaunchResult * _Nullable result, NSError * _Nullable error))completion {
  __block __weak QNProductCenterManager *weakSelf = self;
  
  [_apiClient launchRequest:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
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
  
  [_apiClient purchaseRequestWith:product transaction:transaction completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
    QNPurchaseCompletionHandler _purchasingBlock = weakSelf.purchasingBlocks[product.productIdentifier];
    
    @synchronized (self) {
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
    run_block_on_main(_purchasingBlock, launchResult.permissions, error, NO);
  }];
}

- (void)handleFailedTransaction:(SKPaymentTransaction *)transaction forProduct:(SKProduct *)product {
  NSError *error = [QNErrors errorFromTransactionError:transaction.error];
  
  QNPurchaseCompletionHandler _purchasingBlock = _purchasingBlocks[product.productIdentifier];
  if (_purchasingBlock) {
    run_block_on_main(_purchasingBlock, nil, error, error.code == QNErrorCancelled);
    @synchronized (self) {
      [_purchasingBlocks removeObjectForKey:product.productIdentifier];
    }
  }
}

@end
