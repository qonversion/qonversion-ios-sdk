#import "QNProductCenterManager.h"
#import "QNInMemoryStorage.h"
#import "QNUserDefaultsStorage.h"
#import "QNStoreKitService.h"

@interface QNProductCenterManager()

@property (nonatomic) QNStoreKitService *storeKitService;
@property (nonatomic) QNInMemoryStorage *inMemoryStorage;
@property (nonatomic) QNUserDefaultsStorage *persistentStorage;

@property (nonatomic, strong) NSString *purchasingCurrently;

@end

@implementation QNProductCenterManager

- (instancetype)init {
  self = super.init;
  if (self) {
    _storeKitService = [[QNStoreKitService alloc] initWithDelegate:self];
    
    _inMemoryStorage = [[QNInMemoryStorage alloc] init];
    _persistentStorage = [[QNUserDefaultsStorage alloc] init];
    
    _purchasingCurrently = NULL;
  }
  
  return self;
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

@end
