#import <StoreKit/StoreKit.h>

#import "Qonversion.h"

#import "QNKeeper.h"
#import "QNAPIClient.h"
#import "QNErrors.h"
#import "QNProduct+Protected.h"
#import "QNUserPropertiesManager.h"
#import "QNProductCenterManager.h"
#import "QNAttributionManager.h"
#import "QNProductCenterManager.h"
#import "QNProperties.h"

static NSString * const kProductsResult = @"qonversion.products.result";
static NSString * const kUserDefaultsSuiteName = @"qonversion.user.defaults";

@interface Qonversion()

//@property (nonatomic, strong) QNUserPropertiesManager *propertiesManager;
//@property (nonatomic, strong) QNProductCenterManager *productCenterManager;
//@property (nonatomic, strong) QNAttributionManager *attributionManager;

@property (nonatomic, assign, readwrite) BOOL launchingFinished;

@property (nonatomic, assign) BOOL debugMode;

@end

@implementation Qonversion

// MARK: - Public

+ (void)launchWithKey:(nonnull NSString *)key {
  [self launchWithKey:key completion:nil];
}

+ (void)launchWithKey:(nonnull NSString *)key completion:(QNPurchaseCompletionHandler)completion {
  
  //[[QNAPIClient shared] setApiKey:key];
  //[[Qonversion sharedInstance].productCenterManager]
  // [[Qonversion sharedInstance].productCenterManager] launchWithCompletion:completion];
}

+ (void)setDebugMode:(BOOL)debugMode {
  [Qonversion sharedInstance]->_debugMode = debugMode;
}

+ (void)addAttributionData:(NSDictionary *)data fromProvider:(QNAttributionProvider)provider {
 // [[Qonversion sharedInstance].attributionManager addAttributionData:data fromProvider:provider];
}

+ (void)setProperty:(QNProperty)property value:(NSString *)value {
  NSString *key = [QNProperties keyForProperty:property];
  
  if (key) {
    [self setUserProperty:key value:value];
  }
}

+ (void)setUserProperty:(NSString *)property value:(NSString *)value {
 // [[Qonversion sharedInstance].propertiesManager setUserProperty:property value:value];
}

+ (void)checkPermissions:(QNPermissionCompletionHandler)result {
//  [[Qonversion sharedInstance].productCenterManager checkPermissions:result];
}

+ (void)purchase:(NSString *)productID result:(QNPurchaseCompletionHandler)result {
//  [[Qonversion sharedInstance].productCenterManager purchase:productID result:result];
}

+ (QNProduct *)productFor:(NSString *)productID {
//  return [[Qonversion sharedInstance].productCenterManager productFor:productID];
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
//    _propertiesManager = [[QNUserPropertiesManager alloc] init];
//    _productCenterManager = [[QNProductCenterManager alloc] init];
//    _attributionManager = [[QNAttributionManager alloc] init];
    
    _launchingFinished = NO;
    _debugMode = NO;
  }
  
  return self;
}

@end
