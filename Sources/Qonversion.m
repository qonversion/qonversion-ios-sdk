#import "Qonversion.h"
#import "Keeper.h"
#import "QNConstants.h"
#import "QNMapper.h"
#import "QInMemoryStorage.h"
#import "QUserDefaultsStorage.h"
#import "QNDevice.h"
#import "QNRequestBuilder.h"
#import "QNRequestSerializer.h"
#import "QNErrors.h"
#import "QNStoreKitSugare.h"
#import "QNProduct+Protected.h"

#import <net/if.h>
#import <net/if_dl.h>
#import <sys/socket.h>
#import <sys/sysctl.h>
#import <sys/types.h>

#import <UIKit/UIKit.h>

static NSString * const kBackgrounQueueName = @"qonversion.background.queue.name";
static NSString * const kPermissionsResult = @"qonversion.permissions.result";
static NSString * const kProductsResult = @"qonversion.products.result";
static NSString * const kUserDefaultsSuiteName = @"qonversion.user.defaults";

@interface Qonversion() <SKPaymentTransactionObserver, SKProductsRequestDelegate>

@property (nonatomic, strong) NSOperationQueue *backgroundQueue;


@property (nonatomic, strong) QNRequestBuilder *requestBuilder;
@property (nonatomic, strong) QNRequestSerializer *requestSerializer;
@property (nonatomic) QInMemoryStorage *inMemoryStorage;
@property (nonatomic) QUserDefaultsStorage *persistentStorage;
@property (nonatomic) QonversionPurchaseCompletionHandler purchasingBlock;

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

+ (void)launchWithKey:(nonnull NSString *)key completion:(nullable void (^)(NSString *uid))completion {
  [Qonversion sharedInstance]->_requestBuilder = [[QNRequestBuilder alloc] initWithKey:key];
  
  [SKPaymentQueue.defaultQueue addTransactionObserver:Qonversion.sharedInstance];
  [[Qonversion sharedInstance] launchWithKey:key completion:completion];
}

+ (void)setDebugMode:(BOOL)debugMode {
  [Qonversion sharedInstance]->_debugMode = debugMode;
}

+ (void)addAttributionData:(NSDictionary *)data fromProvider:(QonversionAttributionProvider)provider {
  [[Qonversion sharedInstance] addAttributionData:data fromProvider:provider];
}

+ (void)setProperty:(QNProperty)property value:(NSString *)value {
  NSString *key = [QNProperties keyForProperty:property];
  
  if (key) {
    [self setUserProperty:key value:value];
  }
}

+ (void)setUserProperty:(NSString *)property value:(NSString *)value {
  if ([QNProperties checkProperty:property] && [QNProperties checkValue:value]) {
    [[Qonversion sharedInstance] setUserProperty:property value:value];
  }
}

+ (void)checkPermissions:(QNPermissionCompletionHandler)result {
  [[Qonversion sharedInstance] checkPermissions:result];
}

+ (void)purchase:(NSString *)productID result:(QonversionPurchaseCompletionHandler)result {
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

- (NSURLSession *)session {
  return [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration];
}

- (instancetype)init {
  self = super.init;
  if (self) {
    _inMemoryStorage = [[QInMemoryStorage alloc] init];
    _persistentStorage = [[QUserDefaultsStorage alloc] init];
    
    [_persistentStorage setUserDefaults:[[NSUserDefaults alloc] initWithSuiteName:kUserDefaultsSuiteName]];
    
    _requestSerializer = [[QNRequestSerializer alloc] init];
    _updatingCurrently = NO;
    _launchingFinished = NO;
    _debugMode = NO;
    _device = [[QNDevice alloc] init];
    
    _backgroundQueue = [[NSOperationQueue alloc] init];
    [_backgroundQueue setMaxConcurrentOperationCount:1];
    [_backgroundQueue setSuspended:NO];
    
    _backgroundQueue.name = kBackgrounQueueName;
    
    _permissionsBlocks = [[NSMutableArray alloc] init];
    [self addObservers];
    [self collectIntegrationsData];
  }
  return self;
}

- (void)addAttributionData:(NSDictionary *)data fromProvider:(QonversionAttributionProvider)provider {
  double delayInSeconds = 5.0;
  dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
  
  dispatch_after(popTime, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
    NSDictionary *body = [_requestSerializer attributionDataWithDict:data fromProvider:provider];
    NSURLRequest *request = [_requestBuilder makeAttributionRequestWith:body];
    
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

- (void)purchase:(NSString *)productID result:(QonversionPurchaseCompletionHandler)result {
  
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

- (void)launchWithKey:(nonnull NSString *)key completion:(nullable void (^)(NSString *uid))completion {
  
  NSDictionary *launchData = [self->_requestSerializer launchData];
  NSURLRequest *request = [self->_requestBuilder makeInitRequestWith:launchData];
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
        Keeper.userID = model.result.uid;
        [self->_requestBuilder setUserID:model.result.uid];
      }
      
      if (completion) {
        completion(model.result.uid);
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

- (void)setUserProperty:(NSString *)property value:(NSString *)value {
  [self runOnBackgroundQueue:^{
    [self->_inMemoryStorage storeObject:value forKey:property];
    [self sendPropertiesWithDelay:kQPropertiesSendingPeriodInSeconds];
  }];
}

- (void)addObservers {
  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
  [center addObserver:self
             selector:@selector(enterBackground)
                 name:UIApplicationDidEnterBackgroundNotification
               object:nil];
}

- (void)removeObservers {
  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
  [center removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
}

- (void)dealloc {
  [self removeObservers];
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

- (void)enterBackground {
  [self sendPropertiesInBackground];
}

- (void)sendPropertiesWithDelay:(int)delay {
  if (!_sendingScheduled) {
    _sendingScheduled = YES;
    __block __weak Qonversion *weakSelf = self;
    [_backgroundQueue addOperationWithBlock:^{
      dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf performSelector:@selector(sendPropertiesInBackground) withObject:nil afterDelay:delay];
      });
    }];
  }
}

- (void)sendPropertiesInBackground {
  _sendingScheduled = NO;
  [self sendProperties];
}

- (void)sendProperties {
  if ([QNUtils isEmptyString:_requestBuilder.apiKey]) {
    QONVERSION_ERROR(@"ERROR: apiKey cannot be nil or empty, set apiKey with launchWithKey:");
    return;
  }
  
  @synchronized (self) {
    if (_updatingCurrently) {
      return;
    }
    _updatingCurrently = YES;
  }
  
  [self runOnBackgroundQueue:^{
    NSDictionary *properties = [self->_inMemoryStorage.storageDictionary copy];
    
    if (!properties || ![properties respondsToSelector:@selector(valueForKey:)]) {
      self->_updatingCurrently = NO;
      return;
    }
    
    if (properties.count == 0) {
      self->_updatingCurrently = NO;
      return;
    }
    
    NSURLRequest *request = [_requestBuilder makePropertiesRequestWith:@{@"properties": properties}];
    
    __block __weak Qonversion *weakSelf = self;
    [self dataTaskWithRequest:request completion:^(NSDictionary *dict) {
      if (dict && [dict respondsToSelector:@selector(valueForKey:)]) {
        QONVERSION_LOG(@"Properties Request Log Response:\n%@", dict);
      }
      weakSelf.updatingCurrently = NO;
      [weakSelf clearProperties:properties];
    }];
  }];
}

- (void)clearProperties:(NSDictionary *)properties {
  [self runOnBackgroundQueue:^{
    if (!properties || ![properties respondsToSelector:@selector(valueForKey:)]) {
      return;
    }
    
    for (NSString *key in properties.allKeys) {
      [self->_inMemoryStorage removeObjectForKey:key];
    }
  }];
}

- (BOOL)runOnBackgroundQueue:(void (^)(void))block {
  if ([[NSOperationQueue currentQueue].name isEqualToString:kBackgrounQueueName]) {
    QONVERSION_LOG(@"Already running in the background.");
    block();
    return NO;
  } else {
    [_backgroundQueue addOperationWithBlock:block];
    return YES;
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
  NSURLRequest *request = [self->_requestBuilder makePurchaseRequestWith:body];
  
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
    
    QonversionPurchaseCompletionHandler checkBlock = [self purchasingBlock];
    run_block_on_main(checkBlock, model.result.permissions, model.error, transaction.isCancelled);
    self->_purchasingBlock = nil;
  }] resume];
}

@end
