#import "QNAttributionManager.h"
#import "QNAPIClient.h"
#import "QNUtils.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"

// Delay before the attempt that is made even when the first token was sent successfully.
// Apple registers the attribution record with a delay, so a token requested at launch may be
// unresolvable while a token requested a few minutes later resolves.
static NSTimeInterval const kQNUnconditionalAttributionDelay = 360;

// The attempt number of that unconditional attempt. It is deliberately outside
// -attributionAttemptDelays, so the attempt never schedules a follow-up of its own.
static NSUInteger const kQNUnconditionalAttributionAttempt = NSUIntegerMax - 1;

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

- (void)addAppleSearchAttributionData {
  [self scheduleAppleSearchAttributionDataFetchWithAttempt:0];
  [self scheduleUnconditionalAppleSearchAttributionDataFetch];
}

// Delay before every attempt, keyed by the attempt number. An attempt that is not
// in the map is not made at all, so the map also defines how many attempts there are.
- (NSDictionary<NSNumber *, NSNumber *> *)attributionAttemptDelays {
  return @{@0: @5, @1: @30, @2: @120, @3: @600};
}

// Apple issues the token from its server, so the first attempt fails on a restricted network.
// Retry within the same launch instead of losing the attempt until the next one.
- (void)scheduleAppleSearchAttributionDataFetchWithAttempt:(NSUInteger)attempt {
  NSNumber *delay = [self attributionAttemptDelays][@(attempt)];
  if (delay == nil) {
    return;
  }

  double delayInSeconds = delay.doubleValue;
  dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
  dispatch_after(popTime, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
    [self fetchAppleSearchAttributionDataWithAttempt:attempt];
  });
}

// A token that reached the API without an error may still be unresolvable on Apple's side,
// and the SDK never learns about that. This attempt requests a fresh token regardless of how
// the first one went, and is made once per launch.
- (void)scheduleUnconditionalAppleSearchAttributionDataFetch {
  dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kQNUnconditionalAttributionDelay * NSEC_PER_SEC));
  dispatch_after(popTime, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
    [self fetchAppleSearchAttributionDataWithAttempt:kQNUnconditionalAttributionAttempt];
  });
}

// AAAttributionErrorCode: 1 — networkError, 2 — internalError. Both are transient.
// 3 — platformNotSupported, retrying it never helps.
- (BOOL)isRetriableAttributionTokenError:(NSError *)error {
  return error == nil || error.code == 1 || error.code == 2;
}

- (void)fetchAppleSearchAttributionDataWithAttempt:(NSUInteger)attempt {
#if TARGET_OS_IOS || TARGET_OS_VISION
  NSString *token;
  NSTimeInterval requestTimestamp = [NSDate date].timeIntervalSince1970;
  BOOL shouldRetry = NO;

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
      // NSInvocation copies the argument bytes, so it needs the address of the NSError ** value.
      NSError * __autoreleasing *errorPointer = &error;
      [invocation setArgument:&errorPointer atIndex:2];
      [invocation invoke];

      if (error) {
        QONVERSION_LOG(@"❌ AdServices attributionTokenWithError failed, code: %ld", (long)error.code);
      }

      NSString * __unsafe_unretained tempResult = nil;
      [invocation getReturnValue:&tempResult];
      token = tempResult;

      shouldRetry = token.length == 0 && [self isRetriableAttributionTokenError:error];
    }
  }

  if (token.length > 0) {
    QONVERSION_LOG(@"✅ AdServices token fetched");
    NSDictionary *attributionData = @{@"token": token, @"requested_at": @(requestTimestamp)};
    [self.client attributionRequest:QONAttributionProviderAppleAdServices data:attributionData completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
      if (error) {
        QONVERSION_LOG(@"❌ AdServices attribution request failed: %@", error.localizedDescription);
        // A token minted while Apple was unreachable is never resolvable, so the next
        // attempt requests a new token instead of resending this one.
        [self scheduleAppleSearchAttributionDataFetchWithAttempt:attempt + 1];
      }
    }];
    return;
  } else {
    if (shouldRetry) {
      [self scheduleAppleSearchAttributionDataFetchWithAttempt:attempt + 1];
    }

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
    if (error || attributionDetails.count == 0) {
      QONVERSION_LOG(@"⚠️ iAd attribution details are not available");
      return;
    }

    [self sendAttributionData:attributionDetails provider:QONAttributionProviderAppleSearchAds];
  }];
}

- (void)sendAttributionData:(NSDictionary *)attributionData provider:(QONAttributionProvider)provider {
  [self.client attributionRequest:provider data:attributionData completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) { }];
}

@end

#pragma clang diagnostic pop
