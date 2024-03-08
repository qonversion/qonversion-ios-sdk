#import "QNAttributionManager.h"
#import "QNAPIClient.h"
#import "QNUtils.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"

@interface QNAttributionManager()

@property (nonatomic, strong) QNAPIClient *client;

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
    
    [self.client attributionRequest:provider data:data completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
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
  NSString *token;
  NSTimeInterval requestTimestamp = [NSDate date].timeIntervalSince1970;
  
  if (@available(iOS 14.3, *)) {
    Class attributionClass = NSClassFromString(@"AAAttribution");
    if (attributionClass == nil) {
      QONVERSION_LOG(@"⚠️ AdServices framework not found. Make sure that you import AdServices");
    }
    
    SEL tokenSelector = NSSelectorFromString(@"attributionTokenWithError:");
    if (![attributionClass respondsToSelector:tokenSelector]) {
      QONVERSION_LOG(@"⚠️ attributionTokenWithError method not found. Make sure that you import AdServices");
    } else {
      QONVERSION_LOG(@"✅ AdServices framework found successfully");
      
      NSMethodSignature *methodSignature = [attributionClass methodSignatureForSelector:tokenSelector];
      NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSignature];
      invocation.selector = tokenSelector;
      invocation.target = attributionClass;
      
      __autoreleasing NSError *error;
      [invocation setArgument:&error atIndex:2];
      [invocation invoke];
      
      if (error) {
        QONVERSION_LOG(@"❌ AdServices attributionTokenWithError failed");
      }

      NSString * __unsafe_unretained tempResult = nil;
      [invocation getReturnValue:&tempResult];
      token = tempResult;
    }
  }

  if (token.length > 0) {
    QONVERSION_LOG(@"✅ AdServices token fetched");
    [self sendAttributionData:@{@"token": token, @"requested_at": @(requestTimestamp)} provider:QONAttributionProviderAppleAdServices];
    return;
  } else {
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
  }
#endif
}

- (void)tryToFetchAppleSearchAttributionData:(id)ADClientSharedClientInstance {
  SEL iAdDetailsSelector = NSSelectorFromString(@"requestAttributionDetailsWithBlock:");
  if (![ADClientSharedClientInstance respondsToSelector:iAdDetailsSelector]) {
    return;
  }
  
  [ADClientSharedClientInstance performSelector:iAdDetailsSelector
                                     withObject:^(NSDictionary *attributionDetails, NSError *error) {
    [self sendAttributionData:attributionDetails provider:QONAttributionProviderAppleSearchAds];
  }];
}

- (void)sendAttributionData:(NSDictionary *)attributionData provider:(QONAttributionProvider)provider {
  [self.client attributionRequest:provider data:attributionData completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) { }];
}

@end

#pragma clang diagnostic pop
