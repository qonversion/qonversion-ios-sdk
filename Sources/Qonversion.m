#import "Qonversion.h"

#import "QNKeeper.h"
#import "QNConstants.h"
#import "QNMapper.h"
#import "QNUserDefaultsStorage.h"
#import "QNDevice.h"
#import "QNErrors.h"
#import "QNStoreKitSugare.h"
#import "QNProduct+Protected.h"
#import "QNAPIClient.h"
#import "QNUserPropertiesManager.h"

static NSString * const kPermissionsResult = @"qonversion.permissions.result";
static NSString * const kProductsResult = @"qonversion.products.result";
static NSString * const kUserDefaultsSuiteName = @"qonversion.user.defaults";

@interface Qonversion()

@property (nonatomic, strong) QNUserPropertiesManager *propertiesManager;
@property (nonatomic, strong) QNRequestSerializer *requestSerializer;

@property (nonatomic) QNUserDefaultsStorage *persistentStorage;
@property (nonatomic) QNPurchaseCompletionHandler purchasingBlock;

@property (nonatomic, copy) NSMutableArray *permissionsBlocks;

@property (nonatomic, strong) QNDevice *device;

@property (nonatomic, assign, readwrite) BOOL sendingScheduled;
@property (nonatomic, assign, readwrite) BOOL updatingCurrently;
@property (nonatomic, assign, readwrite) BOOL launchingFinished;

@property (nonatomic, assign) BOOL debugMode;

@end

@implementation Qonversion

// MARK: - Public

+ (void)launchWithKey:(nonnull NSString *)key {
  [self launchWithKey:key completion:nil];
}

+ (void)launchWithKey:(nonnull NSString *)key completion:(QNPurchaseCompletionHandler)completion {
  [[QNAPIClient shared] setApiKey:key];
  
  // TODO
  // Product Center
  [[Qonversion sharedInstance] launchWithKey:key completion:completion];
}

+ (void)setDebugMode:(BOOL)debugMode {
  [Qonversion sharedInstance]->_debugMode = debugMode;
}

+ (void)addAttributionData:(NSDictionary *)data fromProvider:(QNAttributionProvider)provider {
  [[Qonversion sharedInstance] addAttributionData:data fromProvider:provider];
}

+ (void)setProperty:(QNProperty)property value:(NSString *)value {
  NSString *key = [QNProperties keyForProperty:property];
  
  if (key) {
    [self setUserProperty:key value:value];
  }
}

+ (void)setUserProperty:(NSString *)property value:(NSString *)value {
  [[[Qonversion sharedInstance] propertiesManager] setUserProperty:property value:value];
}

+ (void)checkPermissions:(QNPermissionCompletionHandler)result {
  [[Qonversion sharedInstance] checkPermissions:result];
}

+ (void)purchase:(NSString *)productID result:(QNPurchaseCompletionHandler)result {
  [[Qonversion sharedInstance] purchase:productID result:result];
}

+ (QNProduct *)productFor:(NSString *)productID {
  return [[Qonversion sharedInstance] productFor:productID];
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

// MARK: - Private

+ (instancetype)sharedInstance {
  static id shared = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    shared = self.new;
  });
  
  return shared;
}

- (instancetype)init {
  self = super.init;
  if (self) {
    _persistentStorage = [[QNUserDefaultsStorage alloc] init];
    
    _propertiesManager = [[QNUserPropertiesManager alloc] init];
    
    [_persistentStorage setUserDefaults:[[NSUserDefaults alloc] initWithSuiteName:kUserDefaultsSuiteName]];
    
    _updatingCurrently = NO;
    _launchingFinished = NO;
    _debugMode = NO;
    _device = [[QNDevice alloc] init];
    
    _permissionsBlocks = [[NSMutableArray alloc] init];
    [self collectIntegrationsData];
  }
  return self;
}

- (void)addAttributionData:(NSDictionary *)data fromProvider:(QNAttributionProvider)provider {
  double delayInSeconds = 5.0;
  dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
  
  dispatch_after(popTime, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
    NSDictionary *body = [_requestSerializer attributionDataWithDict:data fromProvider:provider];
    NSURLRequest *request = [[self requestBuilder] makeAttributionRequestWith:body];
    
    [self dataTaskWithRequest:request completion:^(NSDictionary *dict) {
      if (dict && [dict respondsToSelector:@selector(valueForKey:)]) {
        QONVERSION_LOG(@"Attribution Request Log Response:\n%@", dict);
      }
    }];
  });
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

- (QonversionLaunchComposeModel *)launchModel {
  return [self.persistentStorage loadObjectForKey:kPermissionsResult];
}

- (QNRequestBuilder *)requestBuilder {
  return [QNRequestBuilder shared];
}

- (void)dataTaskWithRequest:(NSURLRequest *)request completion:(void (^)(NSDictionary *dict))completion {
  NSURLSession *session = [[self session] copy];
  [[session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
    if (!data || ![data isKindOfClass:NSData.class]) {
      return;
    }
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (!dict || ![dict respondsToSelector:@selector(valueForKey:)]) {
      return;
    }
    completion(dict);
  }] resume];
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

- (void)collectIntegrationsData {
  __block __weak Qonversion *weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    [weakSelf performSelector:@selector(collectIntegrationsDataInBackground) withObject:nil afterDelay:5];
  });
}

- (void)collectIntegrationsDataInBackground {
  NSString *adjustUserID = _device.adjustUserID;
  if (![QNUtils isEmptyString:adjustUserID]) {
    [Qonversion setUserProperty:keyQNPropertyAdjustADID value:adjustUserID];
  }
  
  NSString *fbAnonID = _device.fbAnonID;
  if (![QNUtils isEmptyString:fbAnonID]) {
    [Qonversion setUserProperty:keyQNPropertyFacebookAnonUserID value:fbAnonID];
  }
  
  NSString *afUserID = _device.afUserID;
  if (![QNUtils isEmptyString:afUserID]) {
    [Qonversion setUserProperty:keyQNPropertyAppsFlyerUserID value:afUserID];
  }
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
