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

@property (nonatomic) QNPurchaseCompletionHandler purchasingBlock;

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
    run_block_on_bg(^void(){
      weakSelf.launchingFinished = YES;
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
    });
  }];
}

- (void)checkPermissions:(QNPermissionCompletionHandler)result {
  if (!result) {
    return;
  }
  
  @synchronized (self) {
    if (!_launchingFinished) {
      [self.permissionsBlocks addObject:result];
      return;
    }
  }
  
  result(self.launchResult.permissions, self.launchError);
}

- (void)purchase:(NSString *)productID result:(QNPurchaseCompletionHandler)result {
  @synchronized (self) {
    if (self.purchasingBlock) {
      QONVERSION_LOG(@"Purchasing in process");
      return;
    }
    
    QNProduct *product = [self qonversionProduct:productID];
    if (product && [_storeKitService purchase:product.storeID]) {
      self.purchasingBlock = result;
      return;
    }
  }

   result(nil, [QNErrors errorWithQNErrorCode:QNErrorProductNotFound], NO);
}

- (void)executePermissionBlocks {
  @synchronized (self) {
    NSMutableArray <QNPermissionCompletionHandler> *_blocks = [self->_permissionsBlocks copy];
    [self->_permissionsBlocks removeAllObjects];

    for (QNPermissionCompletionHandler block in _blocks) {
      block(self.launchResult.permissions ?: @{}, self.launchError);
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

- (void)productsWithIDs:(NSArray<NSString *> *)productIDs completion:(QNProductsCompletionHandler)completion {
  @synchronized (self) {
    if (!_launchingFinished) {
      [self.productsBlocks addObject:completion];
      return;
    }
  }
  
}

- (void)handleProducts:(NSArray<SKProduct *> *)products {
  
}

- (QNProduct *)productAt:(NSString *)productID {
  QNProduct *product = [self qonversionProduct:productID];
  if (product) {
    id skProduct = [_storeKitService productAt:product.storeID];
    if (skProduct) {
      [product setSkProduct:skProduct];
    }
    return product;
  }
  return nil;
}

- (QNProduct * _Nullable)qonversionProduct:(NSString *)productID {
  NSDictionary *products = _launchResult.products ?: @{};
  
  return products[productID];
}

- (void)launch:(void (^)(QNLaunchResult * _Nullable result, NSError * _Nullable error))completion {
  [_apiClient launchRequest:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
    if (error) {
      completion(nil, error);
      return;
    }
    
    QNMapperObject *result = [QNMapper mapperObjectFrom:dict];
    if (result.error) {
      completion(nil, result.error);
      return;
    }
    
    QNLaunchResult *launchResult = [QNMapper fillLaunchResult:result.data];
    completion(launchResult, nil);
  }];
}

// MARK: - QNStoreKitServiceDelegate

- (void)handlePurchasedTransaction:(SKPaymentTransaction *)transaction forProduct:(SKProduct *)product {
  __block __weak QNProductCenterManager *weakSelf = self;
  [self launch:^(QNLaunchResult * _Nullable result, NSError * _Nullable error) {
    if (!weakSelf.purchasingBlock) {
      return;
    }
    
    weakSelf.purchasingBlock(result.permissions, error, NO);
    weakSelf.purchasingBlock = nil;
  }];
}

- (void)handleFailedTransaction:(SKPaymentTransaction *)transaction forProduct:(SKProduct *)product {
  NSError *error = [QNErrors errorFromTransactionError:transaction.error];
  
  if (self.purchasingBlock) {
    self.purchasingBlock(nil, error, error.code == QNErrorCancelled);
    @synchronized (self) {
      self.purchasingBlock = nil;
    }
  }
}

@end
