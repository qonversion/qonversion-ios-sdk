#import "QNUserPropertiesManager.h"
#import "QNInMemoryStorage.h"
#import "QNProperties.h"
#import "QNAPIClient.h"
#import "QNDevice.h"
#import "QNInternalConstants.h"
#import "QNProductCenterManager.h"
#import "QONUserPropertiesMapper.h"
#import "Qonversion.h"

#if !TARGET_OS_OSX
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#import <net/if.h>
#import <net/if_dl.h>
#endif

static NSString * const kBackgroundQueueName = @"qonversion.background.queue.name";

@interface QNUserPropertiesManager()

@property (nonatomic) QNAPIClient *apiClient;

@property (nonatomic, strong) NSOperationQueue *backgroundQueue;

@property (nonatomic) QNInMemoryStorage *inMemoryStorage;

@property (nonatomic, strong) NSMutableArray<QONUserPropertiesEmptyCompletionHandler> *completionBlocks;

@property (nonatomic, assign, readwrite) BOOL sendingScheduled;
@property (nonatomic, assign, readwrite) BOOL updatingCurrently;
@property (nonatomic, assign, readwrite) NSUInteger retryDelay;
@property (nonatomic, assign, readwrite) NSUInteger retriesCounter;

@property (nonatomic, strong) QNDevice *device;

@end

@implementation QNUserPropertiesManager

- (instancetype)init {
  self = super.init;
  if (self) {
    _inMemoryStorage = [[QNInMemoryStorage alloc] init];
    _backgroundQueue = [[NSOperationQueue alloc] init];
    [_backgroundQueue setMaxConcurrentOperationCount:1];
    [_backgroundQueue setSuspended:NO];
    _apiClient = [QNAPIClient shared];
    _mapper = [QONUserPropertiesMapper new];
    
    _completionBlocks = [NSMutableArray new];
    
    _backgroundQueue.name = kBackgroundQueueName;
    _device = QNDevice.current;
    _retryDelay = kQPropertiesSendingPeriodInSeconds;
    _retriesCounter = 0;
    
    [self addObservers];
    [self collectIntegrationsData];
  }
  
  return self;
}

- (void)setUserProperty:(NSString *)property value:(NSString *)value {
  if ([QNProperties checkProperty:property] && [QNProperties checkValue:value]) {
    [self.inMemoryStorage storeObject:value forKey:property];
    [self sendPropertiesWithDelay:self.retryDelay];
  }
}

- (void)addObservers {
  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
  [center addObserver:self selector:@selector(enterBackground) name:DID_ENTER_BACKGROUND_NOTIFICATION_NAME object:nil];
}

- (void)removeObservers {
  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
  [center removeObserver:self name:DID_ENTER_BACKGROUND_NOTIFICATION_NAME object:nil];
}

- (void)dealloc {
  [self removeObservers];
}

- (void)enterBackground {
  [self sendPropertiesInBackground];
}

- (void)forceSendProperties:(QONUserPropertiesEmptyCompletionHandler)completion {
  if (self.inMemoryStorage.storageDictionary.count == 0) {
    completion();
    return;
  }
  
  [self.completionBlocks addObject:completion];
  
  [self sendProperties:YES];
}

- (void)sendPropertiesWithDelay:(NSUInteger)delay {
  if (!_sendingScheduled) {
    _sendingScheduled = YES;
    __block __weak QNUserPropertiesManager *weakSelf = self;
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
  [self sendProperties:NO];
}

- (void)sendProperties:(BOOL)force {
  if ([QNUtils isEmptyString:_apiClient.apiKey]) {
    QONVERSION_ERROR(@"ERROR: apiKey cannot be nil or empty, set apiKey with launchWithKey:");
    return;
  }
  
  @synchronized (self) {
    if (_updatingCurrently && !force) {
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
    
    self.inMemoryStorage.storageDictionary = @{};
    __block __weak QNUserPropertiesManager *weakSelf = self;
    [self.apiClient sendProperties:properties
                        completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
      weakSelf.updatingCurrently = NO;
      
      NSArray *completions = [weakSelf.completionBlocks copy];
      for (QONUserPropertiesEmptyCompletionHandler storedCompletion in completions) {
        storedCompletion();
      }
      
      [weakSelf.completionBlocks removeAllObjects];
      
      if (error) {
        // copy of an existing array to prevent erasing properties set while the current request is in progress
        NSMutableDictionary *allProperties = [self.inMemoryStorage.storageDictionary mutableCopy];
        for (NSString *key in properties.allKeys) {
          if (!allProperties[key]) {
            allProperties[key] = properties[key];
          }
        }
        
        self.inMemoryStorage.storageDictionary = [allProperties copy];
        
        if ([error.domain isEqualToString:QonversionApiErrorDomain] && error.code == QONAPIErrorInvalidClientUID) {
          [weakSelf.productCenterManager launchWithCompletion:^(QONLaunchResult * _Nonnull result, NSError * _Nullable error) {
            [weakSelf retryProperties];
          }];
        } else {
          [weakSelf retryProperties];
        }
      } else {
        weakSelf.retryDelay = kQPropertiesSendingPeriodInSeconds;
        weakSelf.retriesCounter = 0;
      }
    }];
  }];
}

- (void)getUserProperties:(QONUserPropertiesCompletionHandler)completion {
  [self.apiClient getProperties:^(NSArray * _Nullable array, NSError * _Nullable error) {
    if (error) {
      completion(nil, error);
    } else {
      QONUserProperties *properties = [self.mapper mapUserProperties:array];
      completion(properties, nil);
    }
  }];
}

- (void)retryProperties {
  self.retriesCounter += 1;
  
  self.retryDelay = [self countDelay];
  
  [self sendPropertiesWithDelay:self.retryDelay];
}

- (BOOL)runOnBackgroundQueue:(void (^)(void))block {
  if ([[NSOperationQueue currentQueue].name isEqualToString:kBackgroundQueueName]) {
    QONVERSION_LOG(@"Already running in the background.");
    block();
    return NO;
  } else {
    [_backgroundQueue addOperationWithBlock:block];
    return YES;
  }
}

- (void)collectIntegrationsData {
  __block __weak QNUserPropertiesManager *weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    [weakSelf performSelector:@selector(collectIntegrationsDataInBackground) withObject:nil afterDelay:5];
  });
}

- (void)collectIntegrationsDataInBackground {
  NSString *adjustUserID = _device.adjustUserID;
  if (![QNUtils isEmptyString:adjustUserID]) {
    [self setUserProperty:@"_q_adjust_adid" value:adjustUserID];
  }
  
  NSString *fbAnonID = _device.fbAnonID;
  if (![QNUtils isEmptyString:fbAnonID]) {
    [self setUserProperty:@"_q_fb_anon_id" value:fbAnonID];
  }
  
  NSString *afUserID = _device.afUserID;
  if (![QNUtils isEmptyString:afUserID]) {
    [self setUserProperty:@"_q_appsflyer_user_id" value:afUserID];
  }
  
  [self sendPropertiesInBackground];
}

- (NSUInteger)countDelay {
  NSUInteger delay = kQPropertiesSendingPeriodInSeconds + pow(kFactor, self.retriesCounter);
  NSUInteger delta = delay * kJitter;
  delay = delay + arc4random_uniform((uint32_t)(delta + 1));
  delay = MIN(delay, kMaxDelay);
  
  return delay;
}

@end
