#import "Qonversion.h"
#import "Keeper.h"
#import "UserInfo.h"
#import "QConstants.h"
#import "QonversionMapper.h"
#import "QInMemoryStorage.h"
#import "QUserDefaultsStorage.h"
#import "QDevice.h"
#import "QRequestBuilder.h"
#import "QRequestSerializer.h"

#import <net/if.h>
#import <net/if_dl.h>
#import <sys/socket.h>
#import <sys/sysctl.h>
#import <sys/types.h>

#import <UIKit/UIKit.h>

static NSString * const kBackgrounQueueName = @"qonversion.background.queue.name";
static NSString * const kPermissionsResult = @"kPermissionsResult";
static NSString * const kPermissionsResultBlock = @"kPermissionsResultBlock";

@interface Qonversion() <SKPaymentTransactionObserver, SKProductsRequestDelegate>

@property (nonatomic, readonly) NSMutableDictionary *transactions;
@property (nonatomic, readonly) NSMutableDictionary *productRequests;

@property (nonatomic, strong) NSOperationQueue *backgroundQueue;

@property (nonatomic, strong) QRequestBuilder *requestBuilder;
@property (nonatomic, strong) QRequestSerializer *requestSerializer;
@property (nonatomic) QInMemoryStorage *inMemoryStorage;
@property (nonatomic) QUserDefaultsStorage *persistentStorage;

@property (nonatomic, strong) QDevice *device;

@property (nonatomic, assign, readwrite) BOOL sendingScheduled;
@property (nonatomic, assign, readwrite) BOOL updatingCurrently;
@property (nonatomic, assign, readwrite) BOOL initingCurrently;

@property (nonatomic, assign) BOOL debugMode;

@end

@implementation Qonversion

// MARK: - Public

+ (void)setDebugMode:(BOOL)debugMode {
    [Qonversion sharedInstance]->_debugMode = debugMode;
}

+ (void)launchWithKey:(nonnull NSString *)key {
    [self launchWithKey:key userID:NULL];
}

+ (void)launchWithKey:(nonnull NSString *)key userID:(nonnull NSString *)uid {
    [UserInfo saveInternalUserID:uid];
    
    [self launchWithKey:key completion:NULL];
}

+ (void)launchWithKey:(nonnull NSString *)key completion:(nullable void (^)(NSString *uid))completion {
    [Qonversion sharedInstance]->_requestBuilder = [[QRequestBuilder alloc] initWithKey:key];
    
    [SKPaymentQueue.defaultQueue addTransactionObserver:Qonversion.sharedInstance];
    [[Qonversion sharedInstance] launchWithKey:key completion:completion];
}

+ (void)addAttributionData:(NSDictionary *)data fromProvider:(QAttributionProvider)provider {
    [Qonversion addAttributionData:data fromProvider:provider userID:nil];
}

- (void)launchWithKey:(nonnull NSString *)key completion:(nullable void (^)(NSString *uid))completion {
    
    @synchronized (self) {
        if (_initingCurrently) {
            return;
        }
        _initingCurrently = YES;
    }
    
    NSDictionary *launchData = [self->_requestSerializer launchData];
    NSURLRequest *request = [self->_requestBuilder makeInitRequestWith:launchData];
    NSURLSession *session = [[self session] copy];
    
    __block __weak Qonversion *weakSelf = self;
    [[session dataTaskWithRequest:request
                completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        QonversionCheckPermissionCompletionBlock block = [_inMemoryStorage loadObjectForKey:kPermissionsResultBlock];
        
        if (data == NULL && error) {
            block(NULL, error);
            return;
        }
        
        QonversionLaunchComposeModel *model = [[QonversionMapper new] composeLaunchModelFrom:data];
        
        if (model.result && model.result.uid && completion) {
            [weakSelf.persistentStorage setValue:model.result.permissions forKey:kPermissionsResult];
            completion(model.result.uid);
        }
        
        if (block) {
            block(model.result.permissions,  model.error);
        }
        
    }] resume];
}

+ (void)checkUser:(void(^)(QonversionCheckResult *result))result
          failure:(QonversionCheckFailer)failure {
    __block __weak Qonversion *weakSelf = [Qonversion sharedInstance];
    
    [[Qonversion sharedInstance] runOnBackgroundQueue:^{
        [weakSelf checkUser:result failure:failure];
    }];
}

+ (void)setProperty:(QProperty)property value:(NSString *)value {
    NSString *key = [QonversionProperties keyForProperty:property];
    
    if (key) {
        [self setUserProperty:key value:value];
    }
}

+ (void)setUserProperty:(NSString *)property value:(NSString *)value {
    
    if ([QonversionProperties checkProperty:property] && [QonversionProperties checkValue:value]) {
        [[Qonversion sharedInstance] setUserProperty:property value:value];
    }
}

+ (void)addAttributionData:(NSDictionary *)data fromProvider:(QAttributionProvider)provider userID:(nullable NSString *)uid {
    [[Qonversion sharedInstance] addAttributionData:data fromProvider:provider userID:uid];
}

- (void)addAttributionData:(NSDictionary *)data fromProvider:(QAttributionProvider)provider userID:(nullable NSString *)uid {
    double delayInSeconds = 3.0;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    
    dispatch_after(popTime, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
        NSDictionary *body = [_requestSerializer attributionDataWithDict:data fromProvider:provider userID:uid];
        NSURLRequest *request = [_requestBuilder makeAttributionRequestWith:body];
        
        [self dataTaskWithRequest:request completion:^(NSDictionary *dict) {
            if (dict && [dict respondsToSelector:@selector(valueForKey:)]) {
                QONVERSION_LOG(@"Attribution Request Log Response:\n%@", dict);
            }
        }];
    });
}

- (void)serviceLogPurchase:(SKProduct *)product transaction:(SKPaymentTransaction *)transaction {
    [self runOnBackgroundQueue:^{
        NSDictionary *body = [self->_requestSerializer purchaseData:product transaction:transaction];
        NSURLRequest *request = [self->_requestBuilder makePurchaseRequestWith:body];
        
        [self dataTaskWithRequest:request completion:^(NSDictionary *dict) {
            if (dict && [dict respondsToSelector:@selector(valueForKey:)]) {
                QONVERSION_LOG(@"Qonversion Purchase Log Response:\n%@", dict);
            }
        }];
    }];
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

// MARK: - SKPaymentTransactionObserver

- (void)paymentQueue:(nonnull SKPaymentQueue *)queue updatedTransactions:(nonnull NSArray<SKPaymentTransaction *> *)transactions {
    for (SKPaymentTransaction *transaction in transactions) {
        if (transaction.transactionState != SKPaymentTransactionStatePurchased) {
            continue;
        }
        [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
        [self.transactions setObject:transaction forKey:transaction.payment.productIdentifier];
        
        SKProductsRequest *request = [SKProductsRequest.alloc initWithProductIdentifiers:[NSSet setWithObject:transaction.payment.productIdentifier]];
        [self.productRequests setObject:request forKey:transaction.payment.productIdentifier];
        request.delegate = self;
        [request start];
    }
}

// MARK: - SKProductsRequestDelegate

- (void)productsRequest:(nonnull SKProductsRequest *)request didReceiveResponse:(nonnull SKProductsResponse *)response {
    SKProduct *product = response.products.firstObject;
    if (!product) {
        return;
    }
    SKPaymentTransaction *transaction = [self.transactions objectForKey:product.productIdentifier];
    
    if (!transaction) {
        return;
    }
    
    [self serviceLogPurchase:product transaction:transaction];
    [self.transactions removeObjectForKey:product.productIdentifier];
    [self.productRequests removeObjectForKey:product.productIdentifier];
}

- (void)checkUser:(void(^)(QonversionCheckResult *result))result
               failure:(QonversionCheckFailer)failure {
    
    NSString *userID = Keeper.userID;
    if ([QUtils isEmptyString:userID]) {
        failure([QonversionMapper error:@"Could not init user" code:QErrorCodeFailedReceiveData]);
        return;
    }
    
    NSURLRequest *request = [_requestBuilder makeCheckRequest];
    NSURLSession *session = [[self session] copy];
    [[session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error) {
            failure(error);
            return;
        }
        
        QonversionCheckResultComposeModel *model = [[QonversionMapper new] composeModelFrom:data];
        
        if (model.result) {
            result(model.result);
        } else {
            failure(model.error);
        }
    }] resume];
}

+ (void)checkPermissions:(QonversionCheckPermissionCompletionBlock)result {
    [[Qonversion sharedInstance] checkPermissions:result];
}

- (void)checkPermissions:(QonversionCheckPermissionCompletionBlock)result {
    id permissions = [self.persistentStorage loadObjectForKey:kPermissionsResult];
    if (permissions) {
        result(permissions, NULL);
    } else {
        [self.inMemoryStorage setValue:result forKey:kPermissionsResultBlock];
    }
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
        _transactions = [NSMutableDictionary dictionaryWithCapacity:1];
        _productRequests = [NSMutableDictionary dictionaryWithCapacity:1];
        _inMemoryStorage = [[QInMemoryStorage alloc] init];
        _persistentStorage = [[QUserDefaultsStorage alloc] init];
        _updatingCurrently = NO;
        _initingCurrently = NO;
        _debugMode = NO;
        _device = [[QDevice alloc] init];
        _requestBuilder = [[QRequestBuilder alloc] init];
        
        _backgroundQueue = [[NSOperationQueue alloc] init];
        [_backgroundQueue setMaxConcurrentOperationCount:1];
        [_backgroundQueue setSuspended:NO];
        
        _backgroundQueue.name = kBackgrounQueueName;
        
        [self addObservers];
        [self collectIntegrationsData];
    }
    return self;
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
    if (![QUtils isEmptyString:adjustUserID]) {
        [Qonversion setUserProperty:keyQPropertyAdjustADID value:adjustUserID];
    }
    
    NSString *fbAnonID = _device.fbAnonID;
    if (![QUtils isEmptyString:fbAnonID]) {
        [Qonversion setUserProperty:keyQPropertyFacebookAnonUserID value:fbAnonID];
    }
    
    NSString *afUserID = _device.afUserID;
    if (![QUtils isEmptyString:afUserID]) {
        [Qonversion setUserProperty:keyQPropertyAppsFlyerUserID value:afUserID];
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
    if ([QUtils isEmptyString:_requestBuilder.apiKey]) {
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

@end
