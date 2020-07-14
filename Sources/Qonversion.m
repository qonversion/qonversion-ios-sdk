#import "Qonversion.h"

#import "QNKeeper.h"
#import "QNAPIClient.h"
#import "QNErrors.h"
#import "QNProduct+Protected.h"
#import "QNUserPropertiesManager.h"
#import "QNProductCenterManager.h"
#import <StoreKit/StoreKit.h>
#import "QNProductCenterManager.h"
#import "QNProperties.h"

static NSString * const kPermissionsResult = @"qonversion.permissions.result";
static NSString * const kProductsResult = @"qonversion.products.result";
static NSString * const kUserDefaultsSuiteName = @"qonversion.user.defaults";

@interface Qonversion()

@property (nonatomic, strong) QNUserPropertiesManager *propertiesManager;
@property (nonatomic, strong) QNProductCenterManager *productCenterManager;

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
  [[[Qonversion sharedInstance] productCenterManager] checkPermissions:result];
}

+ (void)purchase:(NSString *)productID result:(QNPurchaseCompletionHandler)result {
  [[[Qonversion sharedInstance] productCenterManager] purchase:productID result:result];
}

+ (QNProduct *)productFor:(NSString *)productID {
  return [[Qonversion sharedInstance] productFor:productID];
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
    _propertiesManager = [[QNUserPropertiesManager alloc] init];
    _productCenterManager = [[QNProductCenterManager alloc] init];
    
    [_persistentStorage setUserDefaults:[[NSUserDefaults alloc] initWithSuiteName:kUserDefaultsSuiteName]];
    
    _updatingCurrently = NO;
    _launchingFinished = NO;
    _debugMode = NO;
    
    _permissionsBlocks = [[NSMutableArray alloc] init];
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

@end
