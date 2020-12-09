#import "QNAttributionManager.h"
#import "QNAPIClient.h"
#import "QNUtils.h"

@interface QNAttributionManager()

@property (nonatomic) QNAPIClient *client;

@end

@implementation QNAttributionManager

- (instancetype)init
{
  self = [super init];
  if (self) {
    _client = [QNAPIClient shared];
  }
  
  return self;
}

- (void)addAttributionData:(NSDictionary *)data fromProvider:(NSInteger)provider {
  double delayInSeconds = 5.0;
  dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));

  dispatch_after(popTime, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
    
    [self->_client attributionRequest:provider data:data completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
      if (dict && [dict respondsToSelector:@selector(valueForKey:)]) {
        QONVERSION_LOG(@"Attribution Request Log Response:\n%@", dict);
      }
    }];
  });
}

- (void)addAppleSearchAttributionData {
  double delayInSeconds = 5.0;
  dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
  dispatch_after(popTime, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
    [self fetchAppleSearchAttributionData];
  });
}

- (void)fetchAppleSearchAttributionData {
#if TARGET_OS_IOS
  
  Class ADClientClass = NSClassFromString(@"ADClient");
  if (ADClientClass == nil) {
    QONVERSION_LOG(@"⚠️ iAd framework not found. Make sure that you import iAd");
    return;
  }
  SEL sharedClientSelector = NSSelectorFromString(@"sharedClient");
  if (![ADClientClass respondsToSelector:sharedClientSelector]) {
    QONVERSION_LOG(@"⚠️ sharedClient method not found. Make sure that you import iAd");
    return;
  }
  
  
  id ADClientSharedClientInstance = [ADClientClass performSelector:sharedClientSelector];
  if (ADClientSharedClientInstance == nil) {
    QONVERSION_LOG(@"⚠️ iAd framework not found (ADClientSharedClientInstance is nil). Make sure that you import iAd");
    return;
  }

  QONVERSION_LOG(@"✅ iAd framework found successfully");
  [self tryToFetchAppleSearchAttributionData:ADClientSharedClientInstance];
#endif
}

- (void)tryToFetchAppleSearchAttributionData:(id)ADClientSharedClientInstance {
  SEL iAdDetailsSelector = NSSelectorFromString(@"requestAttributionDetailsWithBlock:");
  if (![ADClientSharedClientInstance respondsToSelector:iAdDetailsSelector]) {
    return;
  }
  
  [ADClientSharedClientInstance performSelector:iAdDetailsSelector
                                     withObject:^(NSDictionary *attributionDetails, NSError *error) {
    
    [self->_client attributionRequest:QNAttributionProviderAppleSearchAds data:attributionDetails completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) { }];
  }];
}

@end
