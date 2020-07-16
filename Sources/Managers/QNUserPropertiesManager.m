#import "QNUserPropertiesManager.h"
#import "QNInMemoryStorage.h"
#import "QNProperties.h"
#import "QNRequestSerializer.h"
#import "QNAPIClient.h"
#import "QNDevice.h"

#import <UIKit/UIKit.h>

static NSString * const kBackgrounQueueName = @"qonversion.background.queue.name";

@interface QNUserPropertiesManager()

@property (nonatomic) QNAPIClient *apiClient;

@property (nonatomic, strong) NSOperationQueue *backgroundQueue;

@property (nonatomic) QNInMemoryStorage *inMemoryStorage;

@property (nonatomic, assign, readwrite) BOOL sendingScheduled;
@property (nonatomic, assign, readwrite) BOOL updatingCurrently;
@property (nonatomic, assign, readwrite) BOOL launchingFinished;

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

    _backgroundQueue.name = kBackgrounQueueName;
    _device = QNDevice.current;
    
    [self addObservers];
    [self collectIntegrationsData];
  }
  
  return self;
}

- (void)setUserProperty:(NSString *)property value:(NSString *)value {
  if ([QNProperties checkProperty:property] && [QNProperties checkValue:value]) {
    [self runOnBackgroundQueue:^{
      [self->_inMemoryStorage storeObject:value forKey:property];
      [self sendPropertiesWithDelay:kQPropertiesSendingPeriodInSeconds];
    }];
  }
}

- (void)setUserID:(NSString *)userID {
  [self setUserProperty:keyQNPropertyUserID value:userID];
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

- (void)enterBackground {
  [self sendPropertiesInBackground];
}

- (void)sendPropertiesWithDelay:(int)delay {
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
  if ([QNUtils isEmptyString:_apiClient.apiKey]) {
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
    
    __block __weak QNUserPropertiesManager *weakSelf = self;
    [self->_apiClient properties:properties
                      completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
      if (!error) {
        weakSelf.updatingCurrently = NO;
        [weakSelf clearProperties:properties];
      }
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

- (void)collectIntegrationsData {
  __block __weak QNUserPropertiesManager *weakSelf = self;
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

@end
