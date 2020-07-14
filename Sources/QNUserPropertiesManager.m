#import "QNUserPropertiesManager.h"
#import "QNInMemoryStorage.h"
#import "QNProperties.h"
#import "QNRequestSerializer.h"
#import "QNRequestBuilder.h"

static NSString * const kBackgrounQueueName = @"qonversion.background.queue.name";

@interface QNUserPropertiesManager()

@property (nonatomic, strong) NSOperationQueue *backgroundQueue;

@property (nonatomic, strong) QNRequestSerializer *requestSerializer;
@property (nonatomic) QNInMemoryStorage *inMemoryStorage;

@property (nonatomic, assign, readwrite) BOOL sendingScheduled;
@property (nonatomic, assign, readwrite) BOOL updatingCurrently;
@property (nonatomic, assign, readwrite) BOOL launchingFinished;

@end

@implementation QNUserPropertiesManager

- (instancetype)init {
  self = super.init;
  if (self) {
    _inMemoryStorage = [[QNInMemoryStorage alloc] init];
    _backgroundQueue = [[NSOperationQueue alloc] init];
    [_backgroundQueue setMaxConcurrentOperationCount:1];
    [_backgroundQueue setSuspended:NO];

    _backgroundQueue.name = kBackgrounQueueName;
    
    [self addObservers];
  }
  
  return self;
}

- (QNRequestBuilder *)requestBuilder {
  return [QNRequestBuilder shared];
}

- (void)setUserProperty:(NSString *)property value:(NSString *)value {
  if ([QNProperties checkProperty:property] && [QNProperties checkValue:value]) {
    [self runOnBackgroundQueue:^{
      [self->_inMemoryStorage storeObject:value forKey:property];
      [self sendPropertiesWithDelay:kQPropertiesSendingPeriodInSeconds];
    }];
  }
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
  if ([QNUtils isEmptyString:[self requestBuilder].apiKey]) {
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
    
    NSURLRequest *request = [[self requestBuilder] makePropertiesRequestWith:@{@"properties": properties}];
    
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
