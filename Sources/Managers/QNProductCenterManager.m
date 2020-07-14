#import "QNProductCenterManager.h"
#import "QNInMemoryStorage.h"
#import "QNUserDefaultsStorage.h"
#import "QNStoreKitService.h"

static NSString * const kPermissionsResult = @"qonversion.permissions.result";
static NSString * const kUserDefaultsSuiteName = @"qonversion.product-center.suite";

@interface QNProductCenterManager()

@property (nonatomic) QNStoreKitService *storeKitService;
@property (nonatomic) QNUserDefaultsStorage *persistentStorage;

@property (nonatomic) QNPurchaseCompletionHandler purchasingBlock;

@property (nonatomic, copy) NSMutableArray *permissionsBlocks;
@property (nonatomic, strong) NSString *purchasingCurrently;

@end

@implementation QNProductCenterManager

- (instancetype)init {
  self = super.init;
  if (self) {
    _storeKitService = [[QNStoreKitService alloc] initWithDelegate:self];
    
    _persistentStorage = [[QNUserDefaultsStorage alloc] init];
    [_persistentStorage setUserDefaults:[[NSUserDefaults alloc] initWithSuiteName:kUserDefaultsSuiteName]];
    
    _purchasingCurrently = NULL;
    _permissionsBlocks = [[NSMutableArray alloc] init];
  }
  
  return self;
}

- (QonversionLaunchComposeModel *)launchModel {
  return [self.persistentStorage loadObjectForKey:kPermissionsResult];
}

- (void)launchWithKey:(nonnull NSString *)key completion:(QNPurchaseCompletionHandler)completion {
  
  NSDictionary *launchData = [self->_requestSerializer launchData];
  NSURLRequest *request = [[self requestBuilder] makeInitRequestWith:launchData];
  NSURLSession *session = [[self session] copy];
  
  [[session dataTaskWithRequest:request
              completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
    
    if (data == NULL && error) {
      QonversionLaunchComposeModel *model = [[QonversionLaunchComposeModel alloc] init];
      model.error = error;
      
      @synchronized (self) {
        [self->_persistentStorage storeObject:model forKey:kPermissionsResult];
        _launchingFinished = YES;
        [self executePermissionBlocks:model];
        
        return;
      }
    }
    
    QonversionLaunchComposeModel *model = [[QNMapper new] composeLaunchModelFrom:data];
    
    @synchronized (self) {
      [self->_persistentStorage storeObject:model forKey:kPermissionsResult];
      _launchingFinished = YES;
    }
    
    if (model) {
      [self executePermissionBlocks:model];
      [self loadProducts:model];
      
      if (model.result.uid) {
        QNKeeper.userID = model.result.uid;
        [[self requestBuilder] setUserID:model.result.uid];
      }
      
      if (completion) {
        // TODO
        //completion(model.result.uid);
      }
    }
    
    
  }] resume];
}


- (void)logPurchase:(SKProduct *)product transaction:(SKPaymentTransaction *)transaction {
  /*
   NSDictionary *body = [self->_requestSerializer purchaseData:product transaction:transaction];
  NSURLRequest *request = [self->_requestBuilder makePurchaseRequestWith:body];
  
  NSURLSession *session = [[self session] copy];
  
  [[session dataTaskWithRequest:request
              completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error)
    {
    if (!data || ![data isKindOfClass:NSData.class]) {
      return;
    }
    
    NSError *jsonError = [[NSError alloc] init];
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    QONVERSION_LOG(@">>> serviceLogPurchase result %@", dict);
  }] resume];
   */
}

- (QNProduct *)productFor:(NSString *)productID {
  QonversionLaunchComposeModel *model = [self launchModel];
  NSDictionary *products = model.result.products ?: @{};
  QNProduct *product = products[productID];
  if (product) {
    id skProduct = products[product.storeID];
    if (skProduct) {
      [product setSkProduct:skProduct];
    }
    return product;
  }
  return nil;
}

- (void)checkPermissions:(QNPermissionCompletionHandler)result {
  
  @synchronized (self) {
    if (!_launchingFinished) {
      if (result) {
        [self.permissionsBlocks addObject:result];
      }
      
      return;
    }
  }
  
  QonversionLaunchComposeModel *model = [self launchModel];
  if (model) {
    result(model.result.permissions, model.error);
  } else {
    QONVERSION_LOG(@">>> Model not found");
  }
}

- (void)purchase:(NSString *)productID result:(QNPurchaseCompletionHandler)result {
  
  /*
    TODO
   self->_purchasingCurrently = NULL;
   QNProduct *product = [self qonversionProduct:productID];
  
  if (product) {
    SKProduct *skProduct = self->_products[product.storeID];
    
    if (skProduct) {
      self->_purchasingCurrently = skProduct.productIdentifier;
      self->_purchasingBlock = result;
      
      SKPayment *payment = [SKPayment paymentWithProduct:skProduct];
      [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
      [[SKPaymentQueue defaultQueue] addPayment:payment];
      return;
    }
  }*/
  
  result(nil, [QNUtils errorWithQonverionErrorCode:QonversionErrorProductNotFound], NO);
}

- (void)executePermissionBlocks:(QonversionLaunchComposeModel *)model {
  
  @synchronized (self) {
    NSMutableArray <QNPermissionCompletionHandler> *_blocks = [self->_permissionsBlocks copy];
    [self->_permissionsBlocks removeAllObjects];
    
    for (QNPermissionCompletionHandler block in _blocks) {
      block(model.result.permissions ?: @{}, model.error);
    }
  }
}

- (void)loadProducts:(QonversionLaunchComposeModel *)model {
  NSArray<QNProduct *> *products = [model.result.products allValues];
  
  NSMutableSet *productsSet = [[NSMutableSet alloc] init];
  if (products) {
    for (QNProduct *product in products) {
      [productsSet addObject:product.storeID];
    }
  }
  
  SKProductsRequest *request = [SKProductsRequest.alloc initWithProductIdentifiers:productsSet];
  [request setDelegate:self];
  [request start];
}

- (SKProduct * _Nullable)productAt:(SKPaymentTransaction *)transaction {
  NSString *productIdentifier = transaction.payment.productIdentifier ?: @"";
  // TODO
  //return self.products[productIdentifier];
}

- (QNProduct * _Nullable)qonversionProduct:(NSString *)productID {
  QonversionLaunchComposeModel *launchResult = [self launchModel];
  NSDictionary *products = launchResult.result.products ?: @{};
  return products[productID];
}

- (void)purchase:(SKProduct *)product transaction:(SKPaymentTransaction *)transaction {
  // Legacy request for storing purchase
  NSDictionary *body = [self->_requestSerializer purchaseData:product transaction:transaction];
  NSURLRequest *request = [[self requestBuilder] makePurchaseRequestWith:body];
  
  NSURLSession *session = [[self session] copy];
  
  [[session dataTaskWithRequest:request
              completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error)
    {
    if (error) {
      // TODO
      // Faield state
      return;
    }
    
    QonversionLaunchComposeModel *model = [[QNMapper new] composeLaunchModelFrom:data];
    
    @synchronized (self) {
      [self->_persistentStorage storeObject:model forKey:kPermissionsResult];
    }
    
    QNPurchaseCompletionHandler checkBlock = [self purchasingBlock];
    run_block_on_main(checkBlock, model.result.permissions, model.error, transaction.isCancelled);
    self->_purchasingBlock = nil;
  }] resume];
}

@end
