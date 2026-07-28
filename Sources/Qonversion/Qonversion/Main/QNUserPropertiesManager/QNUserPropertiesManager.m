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

@property (atomic, strong) NSMutableArray<QONUserPropertiesEmptyCompletionHandler> *completionBlocks;

@property (atomic, assign, readwrite) BOOL sendingScheduled;
@property (atomic, assign, readwrite) BOOL updatingCurrently;
@property (atomic, assign, readwrite) BOOL forceResendRequired;
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
  BOOL completeImmediately = NO;
  BOOL startSend = NO;
  @synchronized (self) {
    if (self.updatingCurrently) {
      // A POST is in flight (it may have already drained the buffer). The
      // waiter enqueue and the follow-up intent must be recorded in the SAME
      // critical section — deciding later would let the in-flight completion
      // drain this waiter before the intent is visible.
      self.forceResendRequired = YES;
      if (completion) {
        [self.completionBlocks addObject:completion];
      }
    } else if (self.inMemoryStorage.storageDictionary.count == 0) {
      // Nothing pending and nothing in flight — the flush is trivially done.
      // Property writers do not take this lock, so a concurrent set can still
      // slip past this check (pre-existing storage race, best effort).
      completeImmediately = YES;
    } else {
      if (completion) {
        [self.completionBlocks addObject:completion];
      }
      startSend = YES;
    }
  }

  if (completeImmediately) {
    if (completion) {
      completion();
    }
    return;
  }

  if (startSend) {
    [self sendProperties:YES];
  }
}

- (void)sendPropertiesWithDelay:(NSUInteger)delay {
  @synchronized (self) {
    if (!self.sendingScheduled) {
      self.sendingScheduled = YES;
      __block __weak QNUserPropertiesManager *weakSelf = self;
      [self.backgroundQueue addOperationWithBlock:^{
        dispatch_async(dispatch_get_main_queue(), ^{
          [weakSelf performSelector:@selector(sendPropertiesInBackground) withObject:nil afterDelay:delay];
        });
      }];
    }
  }
}

- (void)sendPropertiesInBackground {
  @synchronized (self) {
    self.sendingScheduled = NO;
  }
  [self sendProperties];
}

- (void)sendProperties {
  [self sendProperties:NO];
}

- (void)sendProperties:(BOOL)force {
  if ([QNUtils isEmptyString:self.apiClient.apiKey]) {
    QONVERSION_ERROR(@"ERROR: apiKey cannot be nil or empty, set apiKey with launchWithKey:");
    // No request will ever run — release queued force-flush waiters instead of
    // leaving them stuck forever.
    NSArray *completions = @[];
    @synchronized (self) {
      completions = [self.completionBlocks copy];
      [self.completionBlocks removeAllObjects];
    }
    for (QONUserPropertiesEmptyCompletionHandler storedCompletion in completions) {
      if (storedCompletion) {
        storedCompletion();
      }
    }
    return;
  }
  
  @synchronized (self) {
    if (self.updatingCurrently) {
      if (force) {
        // A force flush arrived while a POST is in flight. Starting a parallel
        // POST would let the older response drain the shared completion pool
        // early — mark a follow-up send instead; the in-flight completion
        // triggers it and keeps the waiters queued until it finishes.
        self.forceResendRequired = YES;
      }
      return;
    }
    self.updatingCurrently = YES;
  }

  [self runOnBackgroundQueue:^{
    NSDictionary *properties = [self.inMemoryStorage.storageDictionary copy];

    if (!properties || ![properties respondsToSelector:@selector(valueForKey:)] || properties.count == 0) {
      NSArray *completions = @[];
      BOOL resend = NO;
      @synchronized (self) {
        self.updatingCurrently = NO;
        self.forceResendRequired = NO;
        // Re-check under the lock: a property stored after the empty snapshot
        // was taken must trigger a real send instead of releasing the queued
        // waiters early.
        if (self.inMemoryStorage.storageDictionary.count > 0) {
          resend = YES;
        } else {
          completions = [self.completionBlocks copy];
          [self.completionBlocks removeAllObjects];
        }
      }

      if (resend) {
        [self sendProperties:YES];
        return;
      }

      // Nothing left to send — release any queued force-flush waiters instead
      // of leaving them stuck until the next request.
      for (QONUserPropertiesEmptyCompletionHandler storedCompletion in completions) {
        if (storedCompletion) {
          storedCompletion();
        }
      }
      return;
    }
    
    self.inMemoryStorage.storageDictionary = @{};
    __block __weak QNUserPropertiesManager *weakSelf = self;
    [self.apiClient sendProperties:properties
                        completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
      // Explicit strong capture: the lock token and every state access below
      // must target the same live object (weakSelf alone would silently no-op
      // the critical section if it ever became nil).
      QNUserPropertiesManager *strongSelf = weakSelf;
      if (!strongSelf) {
        return;
      }

      NSArray *completions = @[];
      BOOL followUpSend = NO;
      @synchronized (strongSelf) {
        strongSelf.updatingCurrently = NO;

        // A force flush was swallowed while this POST was in flight and the
        // buffer holds properties that were not part of the sent snapshot —
        // deliver them first and keep the waiters queued until that follow-up
        // request finishes. On error the waiters are released right away (best
        // effort); the data itself is re-merged below and retried with backoff.
        followUpSend = strongSelf.forceResendRequired && !error && strongSelf.inMemoryStorage.storageDictionary.count > 0;
        strongSelf.forceResendRequired = NO;

        if (!followUpSend) {
          completions = [strongSelf.completionBlocks copy];
          [strongSelf.completionBlocks removeAllObjects];
        }
      }

      for (QONUserPropertiesEmptyCompletionHandler storedCompletion in completions) {
        if (storedCompletion) {
          storedCompletion();
        }
      }

      if (error) {
        // copy of an existing array to prevent erasing properties set while the current request is in progress
        NSMutableDictionary *allProperties = [strongSelf.inMemoryStorage.storageDictionary mutableCopy];
        for (NSString *key in properties.allKeys) {
          if (!allProperties[key]) {
            allProperties[key] = properties[key];
          }
        }

        strongSelf.inMemoryStorage.storageDictionary = [allProperties copy];

        if ([error.domain isEqualToString:QonversionErrorDomain] && error.code == QONErrorCodeInvalidClientUID) {
          [strongSelf.productCenterManager launchWithTrigger:QONRequestTriggerUserProperties completion:^(QONLaunchResult * _Nonnull result, NSError * _Nullable error) {
            [weakSelf retryProperties];
          }];
        } else {
          [strongSelf retryProperties];
        }
      } else {
        strongSelf.retryDelay = kQPropertiesSendingPeriodInSeconds;
        strongSelf.retriesCounter = 0;

        if (followUpSend) {
          [strongSelf sendProperties:YES];
        }
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
    [self.backgroundQueue addOperationWithBlock:block];
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
#if !(TARGET_OS_WATCH || TARGET_OS_VISION)
  [self.device adjustUserIDWithCompletion:^(NSString * _Nullable userId) {
    if (![QNUtils isEmptyString:userId]) {
      [self setUserProperty:@"_q_adjust_adid" value:userId];
    }
  }];
  NSString *afUserID = self.device.afUserID;
  if (![QNUtils isEmptyString:afUserID]) {
    [self setUserProperty:@"_q_appsflyer_user_id" value:afUserID];
  }
#endif
  NSString *fbAnonID = self.device.fbAnonID;
  if (![QNUtils isEmptyString:fbAnonID]) {
    [self setUserProperty:@"_q_fb_anon_id" value:fbAnonID];
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
