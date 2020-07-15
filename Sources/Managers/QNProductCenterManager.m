#import "QNProductCenterManager.h"
#import "QNInMemoryStorage.h"
#import "QNUserDefaultsStorage.h"
#import "QNStoreKitService.h"
#import "QNAPIClient.h"
#import "QNMapper.h"
#import "QNLaunchResult.h"
#import "QNMapperObject.h"
#import "QNKeeper.h"

static NSString * const kLaunchResult = @"qonversion.launch.result";
static NSString * const kUserDefaultsSuiteName = @"qonversion.product-center.suite";

@interface QNProductCenterManager()

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
  
  [self launchWithCompletion:^(QNLaunchResult * _Nonnull result, NSError * _Nullable error) {
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
//  NSArray<QNProduct *> *products = [model.result.products allValues];
//
//  NSMutableSet *productsSet = [[NSMutableSet alloc] init];
//  if (products) {
//    for (QNProduct *product in products) {
//      [productsSet addObject:product.storeID];
//    }
//  }
//
//  SKProductsRequest *request = [SKProductsRequest.alloc initWithProductIdentifiers:productsSet];
//  [request setDelegate:self];
//  [request start];
}

//
//- (void)logPurchase:(SKProduct *)product transaction:(SKPaymentTransaction *)transaction {
//  /*
//   NSDictionary *body = [self->_requestSerializer purchaseData:product transaction:transaction];
//  NSURLRequest *request = [self->_requestBuilder makePurchaseRequestWith:body];
//  
//  NSURLSession *session = [[self session] copy];
//  
//  [[session dataTaskWithRequest:request
//              completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error)
//    {
//    if (!data || ![data isKindOfClass:NSData.class]) {
//      return;
//    }
//    
//    NSError *jsonError = [[NSError alloc] init];
//    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
//    QONVERSION_LOG(@">>> serviceLogPurchase result %@", dict);
//  }] resume];
//   */
//}
//
//- (QNProduct *)productFor:(NSString *)productID {
//  QonversionLaunchComposeModel *model = [self launchModel];
//  NSDictionary *products = model.result.products ?: @{};
//  QNProduct *product = products[productID];
//  if (product) {
//    id skProduct = products[product.storeID];
//    if (skProduct) {
//      [product setSkProduct:skProduct];
//    }
//    return product;
//  }
//  return nil;
//}
//
//- (void)checkPermissions:(QNPermissionCompletionHandler)result {
//  
//  @synchronized (self) {
//    if (!_launchingFinished) {
//      if (result) {
//        [self.permissionsBlocks addObject:result];
//      }
//      
//      return;
//    }
//  }
//  
//  QonversionLaunchComposeModel *model = [self launchModel];
//  if (model) {
//    result(model.result.permissions, model.error);
//  } else {
//    QONVERSION_LOG(@">>> Model not found");
//  }
//}
//
//- (void)purchase:(NSString *)productID result:(QNPurchaseCompletionHandler)result {
//  
//  /*
//    TODO
//   self->_purchasingCurrently = NULL;
//   QNProduct *product = [self qonversionProduct:productID];
//  
//  if (product) {
//    SKProduct *skProduct = self->_products[product.storeID];
//    
//    if (skProduct) {
//      self->_purchasingCurrently = skProduct.productIdentifier;
//      self->_purchasingBlock = result;
//      
//      SKPayment *payment = [SKPayment paymentWithProduct:skProduct];
//      [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
//      [[SKPaymentQueue defaultQueue] addPayment:payment];
//      return;
//    }
//  }*/
//  
//  result(nil, [QNErrors errorWithQonverionErrorCode:QNErrorProductNotFound], NO);
//}

//
//- (SKProduct * _Nullable)productAt:(SKPaymentTransaction *)transaction {
//  NSString *productIdentifier = transaction.payment.productIdentifier ?: @"";
//  // TODO
//  //return self.products[productIdentifier];
//}
//
//- (QNProduct * _Nullable)qonversionProduct:(NSString *)productID {
//  QonversionLaunchComposeModel *launchResult = [self launchModel];
//  NSDictionary *products = launchResult.result.products ?: @{};
//  return products[productID];
//}
//
//- (void)purchase:(SKProduct *)product transaction:(SKPaymentTransaction *)transaction {
//  // Legacy request for storing purchase
//  NSDictionary *body = [self->_requestSerializer purchaseData:product transaction:transaction];
//  NSURLRequest *request = [[self requestBuilder] makePurchaseRequestWith:body];
//  
//  NSURLSession *session = [[self session] copy];
//  
//  [[session dataTaskWithRequest:request
//              completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error)
//    {
//    if (error) {
//      // TODO
//      // Faield state
//      return;
//    }
//    
//    QonversionLaunchComposeModel *model = [[QNMapper new] composeLaunchModelFrom:data];
//    
//    @synchronized (self) {
//      [self->_persistentStorage storeObject:model forKey:kLaunchResult];
//    }
//    
//    QNPurchaseCompletionHandler checkBlock = [self purchasingBlock];
//    run_block_on_main(checkBlock, model.result.permissions, model.error, transaction.isCancelled);
//    self->_purchasingBlock = nil;
//  }] resume];
//}

- (void)launch:(void (^)(QNLaunchResult * _Nullable result, NSError * _Nullable error))completion {
  [_apiClient launchWithCompletion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
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
