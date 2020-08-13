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

@interface Qonversion()

@property (nonatomic, strong) QNProductCenterManager *productCenterManager;
@property (nonatomic, strong) QNUserPropertiesManager *propertiesManager;
@property (nonatomic, strong) QNAttributionManager *attributionManager;

@property (nonatomic, assign) BOOL debugMode;

@end

@implementation Qonversion

// MARK: - Public

+ (void)launchWithKey:(nonnull NSString *)key {
  [self launchWithKey:key completion:nil];
}

+ (void)launchWithKey:(nonnull NSString *)key completion:(QNLaunchCompletionHandler)completion {
  [[QNAPIClient shared] setApiKey:key];
  [[QNAPIClient shared] setUserID:[self getUserID:3]];
  [[QNAPIClient shared] setDebug:[Qonversion sharedInstance]->_debugMode];
  
  [[Qonversion sharedInstance].productCenterManager launchWithCompletion:completion];
}

+ (void)setDebugMode {
  [[Qonversion sharedInstance].propertiesManager setUserProperty:@"_q_debug_mode" value:@"YES"];
  
  @synchronized ([Qonversion sharedInstance]) {
    [Qonversion sharedInstance]->_debugMode = YES;
  }
}

+ (void)addAttributionData:(NSDictionary *)data fromProvider:(QNAttributionProvider)provider {
  [[Qonversion sharedInstance].attributionManager addAttributionData:data fromProvider:provider];
}

+ (void)setProperty:(QNProperty)property value:(NSString *)value {
  NSString *key = [QNProperties keyForProperty:property];
  
  if (key) {
    [self setUserProperty:key value:value];
  }
}

+ (void)setUserProperty:(NSString *)property value:(NSString *)value {
  [[Qonversion sharedInstance].propertiesManager setUserProperty:property value:value];
}

+ (void)setUserID:(NSString *)userID {
  [[Qonversion sharedInstance].propertiesManager setUserID:userID];
}

+ (void)checkPermissions:(QNPermissionCompletionHandler)completion {
  [[Qonversion sharedInstance].productCenterManager checkPermissions:completion];
}

+ (void)purchase:(NSString *)productID completion:(QNPurchaseCompletionHandler)completion {
  [[Qonversion sharedInstance].productCenterManager purchase:productID completion:completion];
}

+ (void)products:(QNProductsCompletionHandler)completion {
  return [[Qonversion sharedInstance].productCenterManager products:completion];
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
    _productCenterManager = [[QNProductCenterManager alloc] init];
    _propertiesManager = [[QNUserPropertiesManager alloc] init];
    _attributionManager = [[QNAttributionManager alloc] init];
    
    _debugMode = NO;
  }
  
  return self;
}

+ (NSString*)getUserID:(int) maxAttempts {
  NSString *userID = QNKeeper.userID;
  if (userID == nil && maxAttempts > 0) {
    return [self getUserID:maxAttempts - 1];
  }
  if (userID) {
    return userID;
  }
  
  return @"";
}

+ (void)resetUser {
  QNKeeper.userID = @"";
  [[QNAPIClient shared] setUserID:@""];
}

@end
