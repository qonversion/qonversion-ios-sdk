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

static NSString * const kLaunchResult = @"qonversion.launch.result";
static NSString * const kUserDefaultsSuiteName = @"qonversion.product-center.suite";

@interface QNProductCenterManager() <QNStoreKitServiceDelegate>
 
@property (nonatomic) QNStoreKitService *storeKitService;
@property (nonatomic) QNUserDefaultsStorage *persistentStorage;

@property (nonatomic) QNPurchaseCompletionHandler purchasingBlock;

@property (nonatomic, copy) NSMutableArray *permissionsBlocks;
@property (nonatomic) NSString *purchasingCurrently;
@property (nonatomic) QNAPIClient *apiClient;

@property (nonatomic) QNLaunchResult *launchResult;
@property (nonatomic) NSError *launchError;

@property (nonatomic, assign) BOOL launchingFinished;

@end

@implementation QNProductCenterManager

- (instancetype)init {
  self = super.init;
  if (self) {
    _launchingFinished = NO;
    _launchError = nil;
    _launchResult = nil;
    
    _apiClient = [QNAPIClient shared];
    _storeKitService = [[QNStoreKitService alloc] initWithDelegate:self];
    
    _persistentStorage = [[QNUserDefaultsStorage alloc] init];
    [_persistentStorage setUserDefaults:[[NSUserDefaults alloc] initWithSuiteName:kUserDefaultsSuiteName]];
    
    _purchasingCurrently = NULL;
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
    if (self.purchasingCurrently) {
      QONVERSION_LOG(@"Purchasing in process");
      return;
    }
    self.purchasingCurrently = NULL;
    
    QNProduct *product = [self qonversionProduct:productID];
    if (product && [_storeKitService purchase:product.storeID]) {
      self.purchasingBlock = result;
      self.purchasingCurrently = product.storeID;
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

- (void)logPurchase:(SKProduct *)product transaction:(SKPaymentTransaction *)transaction {
  [[self apiClient] purchaseRequestWith:product transaction:transaction completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
     QONVERSION_LOG(@">>> logPurchase result %@", dict);
  }];
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

@end
