#import "QNProductCenterManager.h"
#import "QNUserDefaultsStorage.h"
#import "QNStoreKitService.h"
#import "QNAPIClient.h"
#import "QNMapper.h"
#import "QONLaunchResult.h"
#import "QNMapperObject.h"
#import "QONProduct.h"
#import "QONErrors.h"
#import "QONEntitlementsUpdateListener.h"
#import "QONDeferredPurchasesListener.h"
#import "QONEntitlementsUpdateListenerAdapter.h"
#import "QONPromoPurchasesDelegate.h"
#import "QONOfferings.h"
#import "QONOffering.h"
#import "QONIntroEligibility.h"
#import "QNServicesAssembly.h"
#import "QNIdentityManagerInterface.h"
#import "QNUserInfoServiceInterface.h"
#import "QNDevice.h"
#import "QNInternalConstants.h"
#import "QONUser+Protected.h"
#import "QONStoreKit2PurchaseModel.h"
#import "QONFallbackService.h"
#import "QONFallbackObject.h"
#import "QONPromotionalOffer.h"
#import "QONPurchaseOptions.h"
#import "QONPurchaseResult+Protected.h"
#import <StoreKit/StoreKit.h>
#import "QONRequestTrigger.h"



static NSString * const kLaunchResult = @"qonversion.launch.result";
static NSString * const kLaunchResultTimeStamp = @"qonversion.launch.result.timestamp";
static NSString * const kUserDefaultsSuiteName = @"qonversion.product-center.suite";
static NSString * const kIdentityMutationSupersededKey = @"qonversion.identity-mutation-superseded";

@interface QNIdentityRequestData : NSObject

@property (nonatomic, copy) NSString *identityID;
@property (nonatomic, strong) NSMutableArray<QONUserInfoCompletionHandler> *completions;

- (instancetype)initWithIdentityID:(NSString *)identityID
                         completion:(nullable QONUserInfoCompletionHandler)completion;
- (void)addCompletion:(nullable QONUserInfoCompletionHandler)completion;

@end

@implementation QNIdentityRequestData

- (instancetype)initWithIdentityID:(NSString *)identityID
                         completion:(nullable QONUserInfoCompletionHandler)completion {
  self = [super init];
  if (self) {
    _identityID = [identityID copy];
    _completions = [NSMutableArray new];
    [self addCompletion:completion];
  }
  return self;
}

- (void)addCompletion:(nullable QONUserInfoCompletionHandler)completion {
  if (completion) {
    [self.completions addObject:[completion copy]];
  }
}

@end

@interface QNProductCenterManager() <QNStoreKitServiceDelegate>

@property (nonatomic, strong) id<QONDeferredPurchasesListener> deferredPurchasesListener;
@property (nonatomic, weak) id<QONPromoPurchasesDelegate> promoPurchasesDelegate;

@property (nonatomic, strong) QNStoreKitService *storeKitService;
@property (nonatomic, strong) id<QNLocalStorage> persistentStorage;
@property (nonatomic, strong) id<QNIdentityManagerInterface> identityManager;
@property (nonatomic, strong) id<QNUserInfoServiceInterface> userInfoService;
@property (nonatomic, strong) QONFallbackService *fallbackService;
@property (nonatomic, strong) QONFallbackObject *fallbackData;

@property (nonatomic, copy) NSArray<SKPaymentTransaction *> *restoredTransactions;

@property (nonatomic, strong) NSMutableDictionary<NSString *, QONPurchaseResultCompletionHandler> *purchasingBlocks;
@property (nonatomic, strong) NSMutableArray<QNRestoreCompletionHandler> *restorePurchasesBlocks;
@property (nonatomic, strong) NSMutableArray<QNRestoreCompletionHandler> *receiptRestoreBlocks;
@property (nonatomic, strong) NSMutableArray<QONEntitlementsCompletionHandler> *entitlementsBlocks;
@property (nonatomic, strong) NSMutableArray<QONProductsCompletionHandler> *productsBlocks;
@property (nonatomic, strong) NSMutableArray<QONOfferingsCompletionHandler> *offeringsBlocks;
@property (nonatomic, strong) NSMutableArray<QONUserInfoCompletionHandler> *userInfoBlocks;
@property (nonatomic, assign) QONEntitlementsCacheLifetime cacheLifetime;
@property (nonatomic, copy) NSDictionary<NSString *, NSArray *> *productsEntitlementsRelation;
@property (nonatomic, copy) NSDictionary<NSString *, QONEntitlement *> *entitlements;
@property (nonatomic, strong) QNAPIClient *apiClient;

@property (nonatomic, strong) QONLaunchResult *launchResult;
@property (nonatomic, strong) NSError *launchError;
@property (nonatomic, strong) QONUser *user;

@property (nonatomic, copy) NSDictionary<NSString *, QONPurchaseOptions *> *processingPurchaseOptions;

@property (atomic, assign) BOOL launchingFinished;
@property (nonatomic, assign) BOOL productsLoading;
@property (atomic, assign) BOOL restoreInProgress;
@property (atomic, assign) BOOL receiptRestoreInProgress;
@property (nonatomic, assign) BOOL awaitingRestoreResult;
@property (atomic, assign) BOOL identityInProgress;
@property (atomic, assign) BOOL identityLogoutInProgress;
@property (atomic, assign) BOOL unhandledLogoutAvailable;
@property (nonatomic, strong) NSLock *identityStateLock;
@property (nonatomic, strong) NSRecursiveLock *identityMutationLock;
@property (nonatomic, strong) NSLock *entitlementsBlocksLock;
@property (nonatomic, strong) NSLock *userInfoBlocksLock;
@property (nonatomic, strong) NSLock *restoreBlocksLock;
@property (nonatomic, strong) NSLock *launchStateLock;
@property (nonatomic, assign) NSUInteger launchesInFlight;
@property (nonatomic, strong, nullable) NSError *pendingLaunchTerminalError;
@property (nonatomic, assign) NSUInteger identityMutationGeneration;
@property (nonatomic, assign) NSUInteger receiptRestoreIdentityMutationGeneration;
@property (nonatomic, assign) NSUInteger transactionsRestoreIdentityMutationGeneration;
@property (nonatomic, strong, nullable) QNIdentityRequestData *activeIdentityRequest;
@property (nonatomic, strong) NSMutableArray<QNIdentityRequestData *> *pendingIdentityRequests;

- (NSError *)identityMutationSupersededError;
- (BOOL)isIdentityMutationSupersededError:(nullable NSError *)error;
- (void)finishReceiptRestoreWithResult:(nullable QONLaunchResult *)result error:(nullable NSError *)error;
- (void)launch:(QONRequestTrigger)requestTrigger
 identityRequest:(nullable QNIdentityRequestData *)identityRequest
expectedIdentityMutationGeneration:(nullable NSNumber *)expectedGeneration
    completion:(void (^)(QONLaunchResult * _Nullable result, NSError * _Nullable error))completion;
- (void)launchWithTrigger:(QONRequestTrigger)requestTrigger
           identityRequest:(nullable QNIdentityRequestData *)identityRequest
expectedIdentityMutationGeneration:(nullable NSNumber *)expectedGeneration
              scopeCommit:(nullable void (^)(QONLaunchResult *result))scopeCommit
                completion:(nullable QONLaunchCompletionHandler)completion;

@end

@implementation QNProductCenterManager

- (instancetype)initWithUserInfoService:(id<QNUserInfoServiceInterface>)userInfoService identityManager:(id<QNIdentityManagerInterface>)identityManager localStorage:(id<QNLocalStorage>)localStorage fallbackService:(QONFallbackService *)fallbackService {
  self = super.init;
  if (self) {
    _launchingFinished = NO;
    _productsLoading = NO;
    _launchError = nil;
    _launchResult = nil;
    _cacheLifetime = QONEntitlementsCacheLifetimeMonth;
    _fallbackService = fallbackService;


    [self supportMigrationFromOldVersions];
    
    _userInfoService = userInfoService;
    _identityManager = identityManager;
    
    _apiClient = [QNAPIClient shared];
    _storeKitService = [[QNStoreKitService alloc] initWithDelegate:self];
    
    _persistentStorage = localStorage;
    [self transferCachedPermissionsIfNeeded];
    _productsEntitlementsRelation = [_persistentStorage loadObjectForKey:kKeyQUserDefaultsProductsPermissionsRelation];
    
    _purchasingBlocks = [NSMutableDictionary new];
    _restorePurchasesBlocks = [NSMutableArray new];
    _receiptRestoreBlocks = [NSMutableArray new];
    _entitlementsBlocks = [NSMutableArray new];
    _productsBlocks = [NSMutableArray new];
    _offeringsBlocks = [NSMutableArray new];
    _userInfoBlocks = [NSMutableArray new];
    _identityStateLock = [NSLock new];
    _identityMutationLock = [NSRecursiveLock new];
    _entitlementsBlocksLock = [NSLock new];
    _userInfoBlocksLock = [NSLock new];
    _restoreBlocksLock = [NSLock new];
    _launchStateLock = [NSLock new];
    _pendingIdentityRequests = [NSMutableArray new];
  }
  
  return self;
}

- (void)updatePurchaseOptions:(QONPurchaseOptions *)purchaseOptions storeProductId:(NSString *)productId {
  NSMutableDictionary<NSString *, QONPurchaseOptions *> *actualPurchaseOptions = [[self actualPurchaseOptions] mutableCopy];
  actualPurchaseOptions[productId] = purchaseOptions;
  
  self.processingPurchaseOptions = [actualPurchaseOptions copy];
  
  [self.persistentStorage storeObject:self.processingPurchaseOptions forKey:kKeyQUserDefaultsPurchaseOptions];
}

- (void)removePurchaseOptionsForStoreProductId:(NSString *)productId {
  [self updatePurchaseOptions:nil storeProductId:productId];
}

- (NSDictionary<NSString *, QONPurchaseOptions *> *)actualPurchaseOptions {
  if (_processingPurchaseOptions) {
    return self.processingPurchaseOptions;
  }
  
  self.processingPurchaseOptions = [_persistentStorage loadObjectForKey:kKeyQUserDefaultsPurchaseOptions];
  
  if (!self.processingPurchaseOptions) {
    self.processingPurchaseOptions = @{};
  }
  
  return self.processingPurchaseOptions;
}

- (void)transferCachedPermissionsIfNeeded {
  BOOL alreadyTransfered = [self.persistentStorage loadBoolforKey:kKeyQPermissionsTransfered];
  if (!alreadyTransfered) {
    NSDictionary<NSString *, QONEntitlement *> *entitlements = [self.persistentStorage loadObjectForKey:kKeyQUserDefaultsPermissions];
    NSTimeInterval cachedPermissionsTimestamp = [self cachedPermissionsTimestamp];
    [self.persistentStorage storeObject:entitlements forKey:kKeyQUserDefaultsPermissions];
    [self.persistentStorage storeDouble:cachedPermissionsTimestamp forKey:kKeyQUserDefaultsPermissionsTimestamp];
    
    [self.persistentStorage storeBool:YES forKey:kKeyQPermissionsTransfered];
  }
}

- (void)supportMigrationFromOldVersions {
  [NSKeyedUnarchiver setClass:[QONLaunchResult class] forClassName:@"QNLaunchResult"];
  [NSKeyedUnarchiver setClass:[QONProduct class] forClassName:@"QNProduct"];
  [NSKeyedUnarchiver setClass:[QONOfferings class] forClassName:@"QNOfferings"];
  [NSKeyedUnarchiver setClass:[QONOffering class] forClassName:@"QNOffering"];
}

- (void)setEntitlementsCacheLifetime:(QONEntitlementsCacheLifetime)cacheLifetime {
  self.cacheLifetime = cacheLifetime;
}

- (void)storeLaunchResultIfNeeded:(QONLaunchResult *)launchResult {
  if (launchResult.timestamp > 0) {
    NSDate *currentDate = [NSDate date];
    [self storeEntitlements:launchResult.entitlements];
    [self.persistentStorage storeDouble:currentDate.timeIntervalSince1970 forKey:kLaunchResultTimeStamp];
    [self.persistentStorage storeObject:launchResult forKey:kLaunchResult];
  }
}

- (QONLaunchResult * _Nullable)cachedLaunchResult {
  QONLaunchResult *result = [self.persistentStorage loadObjectForKey:kLaunchResult];
  
  return result;
}

- (NSTimeInterval)cachedLaunchResultTimeStamp {
  return [self.persistentStorage loadDoubleForKey:kLaunchResultTimeStamp];
}

- (NSDictionary<NSString *, QONProduct *> *)getActualProducts {
  NSDictionary *products = _launchResult.products ?: @{};
  
  if (self.launchError) {
    QONLaunchResult *cachedResult = [self cachedLaunchResult];
    products = cachedResult ? cachedResult.products : products;
    
    if (products.allValues.count == 0) {
      [self actualizeFallbackData];
      products = self.fallbackData.products;
    }
  }
  
  return products;
}

- (void)actualizeFallbackData {
  self.fallbackData = self.fallbackData ?: [self.fallbackService obtainFallbackData];
}

- (QONOfferings * _Nullable)getActualOfferings {
  QONOfferings *offerings = self.launchResult.offerings ?: nil;
  
  if (self.launchError) {
    QONLaunchResult *cachedResult = [self cachedLaunchResult];
    offerings = cachedResult ? cachedResult.offerings : offerings;
    
    if (!offerings) {
      [self actualizeFallbackData];
      offerings = self.fallbackData.offerings;
    }
  }
  
  return offerings;
}

- (BOOL)isUserStable {
  [self.identityStateLock lock];
  BOOL hasIdentityWork = self.activeIdentityRequest != nil || self.pendingIdentityRequests.count > 0;
  [self.identityStateLock unlock];
  return self.launchingFinished
      && !self.identityInProgress
      && !self.identityLogoutInProgress
      && !self.restoreInProgress
      && !self.receiptRestoreInProgress
      && !hasIdentityWork
      && !self.unhandledLogoutAvailable;
}

- (NSError *)identityMutationSupersededError {
  return [NSError errorWithDomain:NSURLErrorDomain
                             code:NSURLErrorCancelled
                         userInfo:@{
                           NSLocalizedDescriptionKey: @"The restore result was superseded by a newer identity operation.",
                           kIdentityMutationSupersededKey: @YES,
                         }];
}

- (BOOL)isIdentityMutationSupersededError:(nullable NSError *)error {
  return [error.userInfo[kIdentityMutationSupersededKey] boolValue];
}

- (void)launchWithTrigger:(QONRequestTrigger)requestTrigger completion:(nullable QONLaunchCompletionHandler)completion {
  [self launchWithTrigger:requestTrigger identityRequest:nil completion:completion];
}

- (void)launchWithTrigger:(QONRequestTrigger)requestTrigger
           identityRequest:(nullable QNIdentityRequestData *)identityRequest
                 completion:(nullable QONLaunchCompletionHandler)completion {
  [self launchWithTrigger:requestTrigger
          identityRequest:identityRequest
expectedIdentityMutationGeneration:nil
              scopeCommit:nil
                completion:completion];
}

- (void)launchWithTrigger:(QONRequestTrigger)requestTrigger
           identityRequest:(nullable QNIdentityRequestData *)identityRequest
expectedIdentityMutationGeneration:(nullable NSNumber *)expectedGeneration
              scopeCommit:(nullable void (^)(QONLaunchResult *result))scopeCommit
                completion:(nullable QONLaunchCompletionHandler)completion {
  __block __weak QNProductCenterManager *weakSelf = self;
  
  [self launch:requestTrigger
identityRequest:identityRequest
expectedIdentityMutationGeneration:expectedGeneration
 completion:^(QONLaunchResult * _Nonnull result, NSError * _Nullable error) {
    if ([weakSelf isIdentityMutationSupersededError:error]) {
      [weakSelf handlePendingRequests:nil];
      if (completion) {
        run_block_on_main(completion, result, error)
      }
      return;
    }

    BOOL mutationLockHeld = NO;
    if (identityRequest) {
      [weakSelf.identityMutationLock lock];
      mutationLockHeld = YES;
      if (![weakSelf isActiveIdentityRequest:identityRequest]) {
        [weakSelf.identityMutationLock unlock];
        return;
      }
    }
    if (scopeCommit && !error) {
      scopeCommit(result);
    }
    [weakSelf storeLaunchResultIfNeeded:result];
    
    weakSelf.launchResult = result;
    weakSelf.launchError = error;

    [weakSelf executeUserBlocks];
    
    NSArray *storeProducts = [weakSelf.storeKitService getLoadedProducts];
    if (!weakSelf.productsLoading && storeProducts.count == 0) {
      [weakSelf loadProducts];
    }

    [weakSelf handlePendingRequests:error];
    
    if (completion) {
      run_block_on_main(completion, result, error)
    }
    
    if (error) {
      QONVERSION_LOG(@"❗️ Request failed %@", error.description);
    }
    if (mutationLockHeld) {
      [weakSelf.identityMutationLock unlock];
    }
  }];
}

- (void)identify:(NSString *)identityId completion:(nullable QONUserInfoCompletionHandler)completion {
  [self.identityMutationLock lock];
  // A newly accepted identity intent supersedes every restore that was
  // accepted against the previous user boundary, even when it coalesces.
  self.identityMutationGeneration += 1;
  self.unhandledLogoutAvailable = NO;
  QNIdentityRequestData *requestToStart = nil;
  [self.identityStateLock lock];
  // Coalesce only adjacent equal requests. A,A shares one network attempt;
  // A,B,A remains three ordered state transitions and ends on A.
  QNIdentityRequestData *coalescingRequest = self.pendingIdentityRequests.lastObject;
  if (!coalescingRequest && [self.activeIdentityRequest.identityID isEqualToString:identityId]) {
    coalescingRequest = self.activeIdentityRequest;
  }
  if ([coalescingRequest.identityID isEqualToString:identityId]) {
    [coalescingRequest addCompletion:completion];
  } else {
    QNIdentityRequestData *request = [[QNIdentityRequestData alloc] initWithIdentityID:identityId
                                                                            completion:completion];
    [self.pendingIdentityRequests addObject:request];
  }
  requestToStart = [self takeNextIdentityRequestIfReadyLocked];
  [self.identityStateLock unlock];

  [self startIdentityRequest:requestToStart];
  [self.identityMutationLock unlock];
}

- (void)processIdentity:(NSString *)identityId {
  [self processIdentity:identityId request:nil];
}

- (void)processIdentity:(NSString *)identityId request:(nullable QNIdentityRequestData *)request {
  NSString *currentUserID = [self.userInfoService obtainUserID];
  
  __block __weak QNProductCenterManager *weakSelf = self;
  [self.identityManager identify:identityId completion:^(NSString *result, NSError * _Nullable error) {
    if (request && ![weakSelf isActiveIdentityRequest:request]) {
      // logout (or another cancellation boundary) won the race. Never apply a
      // late identity response after callers were told the attempt was canceled.
      return;
    }
    if (error) {
      [weakSelf failIdentityRequest:request error:error];
      return;
    }

    [weakSelf.identityMutationLock lock];
    BOOL mutationLockHeld = YES;
    if (request && ![weakSelf isActiveIdentityRequest:request]) {
      [weakSelf.identityMutationLock unlock];
      return;
    }
    // Persistence, the custom identity, and the Remote Config scope commit as
    // one logout-serialized boundary. Whichever owns identityMutationLock
    // first wins; logout can no longer slip between validation and storage.
    // Claim the successful scope/custom-identity commit. This invalidates a
    // restore accepted while the network identity request was still active.
    weakSelf.identityMutationGeneration += 1;
    if (result.length > 0) {
      [weakSelf.userInfoService storeIdentity:result];
    }
    [weakSelf.userInfoService storeCustomIdentityUserID:identityId];
    
    if ([currentUserID isEqualToString:result]) {
      // The uid did not change, but the identity did — user properties and the
      // external identity are now attached, so cached configs may no longer
      // reflect the server-side targeting evaluation. Drop them
      // (non-destructively) so the next remoteConfig call refetches
      // (DEV-1236 B4). Invalidate BEFORE handlePendingRequests: the replay
      // must miss the cache, or queued completions would be served the
      // pre-identify evaluation and orphaned by the cache-hit path.
      [weakSelf.remoteConfigManager invalidateRemoteConfigsCache];
      // Keep isUserStable false through the RC boundary transition. Clearing
      // these earlier opens a window where a concurrent caller can consume a
      // pre-identify warm config before invalidation reaches the RC manager.
      [weakSelf finishIdentityRequest:request error:nil];
      if (mutationLockHeld) {
        [weakSelf.identityMutationLock unlock];
      }
    } else {
      [weakSelf.remoteConfigManager userHasBeenChangedToUserID:result];
      if (mutationLockHeld) {
        [weakSelf.identityMutationLock unlock];
      }

      [weakSelf resetActualPermissionsCache];
      QONLaunchCompletionHandler launchCompletion = ^(QONLaunchResult * _Nonnull result, NSError * _Nullable error) {
        if (request && ![weakSelf isActiveIdentityRequest:request]) {
          return;
        }
        [weakSelf finishIdentityRequest:request error:error];
      };
      if (request) {
        [weakSelf launchWithTrigger:QONRequestTriggerIdentify identityRequest:request completion:launchCompletion];
      } else {
        [weakSelf launchWithTrigger:QONRequestTriggerIdentify completion:launchCompletion];
      }
    }
  }];
}

- (void)logout {
  NSError *cancellationError = [NSError errorWithDomain:NSURLErrorDomain
                                                   code:NSURLErrorCancelled
                                               userInfo:@{NSLocalizedDescriptionKey: @"The identify request was canceled by logout."}];
  [self.identityMutationLock lock];
  [self.identityStateLock lock];
  if (self.identityLogoutInProgress) {
    // A synchronous Remote Config callback may re-enter logout while the
    // outer call still owns this recursive lock. The outer call has already
    // unlinked the identity and is the sole owner of cancellation + scope
    // publication; a nested call must not clear its logical boundary.
    [self.identityStateLock unlock];
    [self.identityMutationLock unlock];
    return;
  }
  // The public logout intent is newer than every previously accepted restore,
  // even when there is no persisted identity left to unlink.
  self.identityMutationGeneration += 1;
  self.identityLogoutInProgress = YES;
  QNIdentityRequestData *activeRequest = self.activeIdentityRequest;
  NSMutableArray<QNIdentityRequestData *> *cancelledRequests = [self.pendingIdentityRequests mutableCopy];
  if (activeRequest) {
    [cancelledRequests insertObject:activeRequest atIndex:0];
  }
  self.activeIdentityRequest = nil;
  [self.pendingIdentityRequests removeAllObjects];
  self.identityInProgress = NO;
  [self.identityStateLock unlock];

  BOOL isLogoutNeeded = [self.identityManager logoutIfNeeded];
  NSString *logoutUserID = nil;
  
  if (isLogoutNeeded) {
    [self.userInfoService storeCustomIdentityUserID:nil];
    [self actualizeUserInfo];
    self.unhandledLogoutAvailable = YES;
    logoutUserID = [self.userInfoService obtainUserID];
    [self resetActualPermissionsCache];
  }

  if (cancelledRequests.count > 0) {
    // Drain the cancelled identity's Remote Config window while logout still
    // owns the mutation boundary. A concurrent identify can only queue here,
    // so this cancellation can never land in the new attempt's window.
    [self.remoteConfigManager userChangingRequestFailedWithError:cancellationError];
  }
  if (isLogoutNeeded) {
    // Publish the successful logout scope last: this clears the cancellation
    // latch and makes the original user the only observable stable scope.
    [self.remoteConfigManager userHasBeenChangedToUserID:logoutUserID];
    self.identityMutationGeneration += 1;
  }

  [self.identityStateLock lock];
  self.identityLogoutInProgress = NO;
  BOOL hasNewIdentityRequest = self.pendingIdentityRequests.count > 0;
  [self.identityStateLock unlock];

  [self.identityMutationLock unlock];

  for (QNIdentityRequestData *request in cancelledRequests) {
    [self deliverIdentityRequest:request error:cancellationError];
  }
  if (hasNewIdentityRequest) {
    // A post-logout identify supersedes the deferred logout launch and will
    // fetch the final user's state itself.
    self.unhandledLogoutAvailable = NO;
    [self handlePendingRequests:nil];
  }
}

- (void)setPromoPurchasesDelegate:(id<QONPromoPurchasesDelegate>)delegate {
  _promoPurchasesDelegate = delegate;
}

- (void)setPurchasesDelegate:(id<QONEntitlementsUpdateListener>)delegate {
  if (delegate) {
    QONEntitlementsUpdateListenerAdapter *adapter = [[QONEntitlementsUpdateListenerAdapter alloc] initWithLegacyListener:delegate];
    _deferredPurchasesListener = adapter;
  } else {
    _deferredPurchasesListener = nil;
  }
}

- (void)setDeferredPurchasesListener:(id<QONDeferredPurchasesListener>)listener {
  _deferredPurchasesListener = listener;
}

- (void)userInfo:(QONUserInfoCompletionHandler)completion {
  [self.userInfoBlocksLock lock];
  if (!self.launchingFinished) {
    [self.userInfoBlocks addObject:completion];
    [self.userInfoBlocksLock unlock];
    return;
  }
  [self.userInfoBlocksLock unlock];
  
  [self actualizeUserInfo];
  QONUser *user = self.user;
  NSError *error = self.launchError;
  run_block_on_main(completion, user, error);
}

- (void)presentCodeRedemptionSheet {
  [self.storeKitService presentCodeRedemptionSheet];
}

- (void)checkEntitlements:(QONEntitlementsCompletionHandler)completion {
  if (!completion) {
    return;
  }

  [self.entitlementsBlocksLock lock];
  [self.entitlementsBlocks addObject:completion];
  [self.entitlementsBlocksLock unlock];
  [self handlePendingRequests:nil];
}

- (void)handleLogout {
  self.unhandledLogoutAvailable = NO;
  [self launchWithTrigger:QONRequestTriggerLogout completion:nil];
}

- (void)purchase:(QONProduct *)product options:(QONPurchaseOptions *)options completion:(QONPurchaseCompletionHandler)completion {
  [self purchase:product.qonversionID purchaseOptions:options completion:completion];
}

- (void)purchase:(NSString *)productID purchaseOptions:(QONPurchaseOptions *)options completion:(QONPurchaseCompletionHandler)completion {
  QONProduct *product = [self QNProduct:productID];
  if (!product) {
    run_block_on_main(completion, @{}, [QONErrors errorWithQONErrorCode:QONErrorCodeProductNotFound], NO);
    return;
  }
  
  // Convert legacy completion to PurchaseResult completion
  QONPurchaseResultCompletionHandler resultCompletion = ^(QONPurchaseResult *result) {
    if (completion) {
      if (result.isSuccessful) {
        run_block_on_main(completion, result.entitlements ?: @{}, nil, NO);
      } else if (result.isCanceledByUser) {
        run_block_on_main(completion, @{}, nil, YES);
      } else if (result.isPending) {
        NSError *pendingError = [QONErrors errorWithQONErrorCode:QONErrorCodePurchasePending];
        run_block_on_main(completion, @{}, pendingError, NO);
      } else {
        NSError *error = result.error ?: [QONErrors errorWithQONErrorCode:QONErrorCodeUnknown];
        run_block_on_main(completion, @{}, error, NO);
      }
    }
  };
  
  [self purchaseWithResult:product 
                   options:options
                completion:resultCompletion];
}

- (void)purchaseWithResult:(QONProduct *)product options:(QONPurchaseOptions *)options completion:(nonnull QONPurchaseResultCompletionHandler)completion {
  if (self.launchMode == QONLaunchModeAnalytics) {
    QONVERSION_LOG(@"⚠️ Making purchases via Qonversion in the Analytics mode can lead to an inconsistent state in the store. Consider switching to the Subscription management mode.");
  }
  
  @synchronized (self) {
    NSArray *storeProducts = [self.storeKitService getLoadedProducts];
    
    if (self.launchError) {
      [self handleLaunchErrorForProduct:product options:options completion:completion];
    } else if (!self.productsLoading && storeProducts.count == 0) {
      [self handleNoProductsForProduct:product options:options completion:completion];
    } else {
      [self handleDirectPurchaseForProduct:product options:options completion:completion];
    }
  }
}

// MARK: - Private Helper Methods

- (void)handleLaunchErrorForProduct:(QONProduct *)product 
                            options:(QONPurchaseOptions *)options 
                         completion:(nonnull QONPurchaseResultCompletionHandler)completion {
  __block __weak QNProductCenterManager *weakSelf = self;
  [self launchWithTrigger:QONRequestTriggerPurchase completion:^(QONLaunchResult * _Nonnull result, NSError * _Nullable error) {
    if ([weakSelf isIdentityMutationSupersededError:error]) {
      [weakSelf handlePurchaseError:error completion:completion];
      return;
    }
    NSDictionary<NSString *, QONProduct *> *products = [weakSelf getActualProducts];
    if (error && products.count == 0) {
      [weakSelf handlePurchaseError:error completion:completion];
      return;
    }
    
    if (weakSelf.productsLoading) {
      [weakSelf prepareDelayedPurchase:product options:options completion:completion];
    } else {
      [weakSelf processPurchase:product options:options completion:completion];
    }
  }];
}

- (void)handleNoProductsForProduct:(QONProduct *)product 
                           options:(QONPurchaseOptions *)options 
                        completion:(nonnull QONPurchaseResultCompletionHandler)completion {
  [self prepareDelayedPurchase:product options:options completion:completion];
  [self loadProducts];
}

- (void)handleDirectPurchaseForProduct:(QONProduct *)product 
                               options:(QONPurchaseOptions *)options 
                            completion:(nonnull QONPurchaseResultCompletionHandler)completion {
  [self processPurchase:product options:options completion:completion];
}

- (void)prepareDelayedPurchase:(QONProduct *)product 
                       options:(QONPurchaseOptions *)options 
                    completion:(nonnull QONPurchaseResultCompletionHandler)completion {
  QONProductsCompletionHandler productsCompletion = ^(NSDictionary<NSString *, QONProduct *> *result, NSError  *_Nullable error) {
    if (error) {
      [self handlePurchaseError:error completion:completion];
      return;
    }
    
    [self processPurchase:product options:options completion:completion];
  };
  
  [self.productsBlocks addObject:productsCompletion];
}

- (void)processPurchase:(QONProduct *)product 
                options:(QONPurchaseOptions *)options 
             completion:(nonnull QONPurchaseResultCompletionHandler)completion {
  
  if (self.purchasingBlocks[product.storeID]) {
    QONVERSION_LOG(@"Purchasing in process");
    return;
  }
  
  NSString *identityId = [self.userInfoService obtainCustomIdentityUserID];
  if (product && [_storeKitService purchase:product.storeID options:options identityId:identityId]) {
    [self updatePurchaseOptions:options storeProductId:product.storeID];
    
    self.purchasingBlocks[product.storeID] = completion;
    
    return;
  }
  
  QONVERSION_LOG(@"❌ Store product with id: %@ not found", product.storeID);
  NSError *error = [QONErrors errorWithQONErrorCode:QONErrorCodeProductNotFound];
  [self handlePurchaseError:error completion:completion];
}

- (void)handlePurchaseError:(NSError *)error 
                 completion:(nonnull QONPurchaseResultCompletionHandler)completion {
  QONPurchaseResult *purchaseResult = [QONPurchaseResult errorWithError:error];
  run_block_on_main(completion, purchaseResult);
}


- (void)restoreReceipt:(QNRestoreCompletionHandler)completion {
  [self.identityMutationLock lock];
  [self.restoreBlocksLock lock];
  if (completion) {
    [self.receiptRestoreBlocks addObject:completion];
  }
  if (self.receiptRestoreInProgress) {
    [self.restoreBlocksLock unlock];
    [self.identityMutationLock unlock];
    return;
  }
  self.receiptRestoreInProgress = YES;
  self.receiptRestoreIdentityMutationGeneration = self.identityMutationGeneration;
  NSUInteger ownerGeneration = self.receiptRestoreIdentityMutationGeneration;
  [self.restoreBlocksLock unlock];
  [self.identityMutationLock unlock];
  
  __block __weak QNProductCenterManager *weakSelf = self;
  [self.storeKitService receipt:^(NSString * _Nonnull receipt) {
    [weakSelf.identityMutationLock lock];
    if (weakSelf.identityMutationGeneration != ownerGeneration) {
      NSError *supersededError = [weakSelf identityMutationSupersededError];
      [weakSelf.identityMutationLock unlock];
      [weakSelf finishReceiptRestoreWithResult:nil error:supersededError];
      [weakSelf handlePendingRequests:nil];
      return;
    }
    [weakSelf launchWithTrigger:QONRequestTriggerRestore
                identityRequest:nil
expectedIdentityMutationGeneration:@(ownerGeneration)
                    scopeCommit:^(QONLaunchResult *result) {
      [weakSelf handleUserSwitchIfNeededWithResult:result];
    }
                      completion:^(QONLaunchResult * _Nonnull result, NSError * _Nullable error) {
      [weakSelf finishReceiptRestoreWithResult:result error:error];
    }];
    [weakSelf.identityMutationLock unlock];
  }];
}

- (void)finishReceiptRestoreWithResult:(nullable QONLaunchResult *)result error:(nullable NSError *)error {
  [self.restoreBlocksLock lock];
  self.receiptRestoreInProgress = NO;
  NSArray<QNRestoreCompletionHandler> *completions = [self.receiptRestoreBlocks copy];
  [self.receiptRestoreBlocks removeAllObjects];
  [self.restoreBlocksLock unlock];

  NSDictionary<NSString *, QONEntitlement *> *entitlements = result.entitlements ?: @{};
  for (QNRestoreCompletionHandler block in completions) {
    dispatch_async(dispatch_get_main_queue(), ^{
      block(entitlements, error);
    });
  }
}

- (void)restoreTransactions:(QNRestoreCompletionHandler)completion {
  [self.identityMutationLock lock];
  [self.restoreBlocksLock lock];
  if (completion != nil) {
    [self.restorePurchasesBlocks addObject:completion];
  }

  if (self.restoreInProgress) {
    [self.restoreBlocksLock unlock];
    [self.identityMutationLock unlock];
    return;
  }

  self.awaitingRestoreResult = YES;
  self.restoreInProgress = YES;
  self.transactionsRestoreIdentityMutationGeneration = self.identityMutationGeneration;
  [self.restoreBlocksLock unlock];
  [self.identityMutationLock unlock];

  [self.storeKitService restore];
}

- (void)actualizeEntitlements:(QONEntitlementsCompletionHandler)completion {
  __block __weak QNProductCenterManager *weakSelf = self;

  [self launchWithTrigger:QONRequestTriggerActualizePermissions completion:^(QONLaunchResult * _Nonnull result, NSError * _Nullable error) {
      if ([weakSelf isIdentityMutationSupersededError:error]) {
        run_block_on_main(completion, @{}, error);
        return;
      }
      weakSelf.unhandledLogoutAvailable = NO;
      NSDictionary<NSString *, QONEntitlement *> *entitlements = result.entitlements;
      NSError *resultError = error;
      if (error && ![weakSelf hasPendingIdentityRequests]) {
        // Preserve backend entitlements when available (e.g. Stripe subscriptions).
        // Only fall back to cache when backend returned no entitlements.
        if (!entitlements || entitlements.count == 0) {
          entitlements = [weakSelf getActualEntitlementsForDefaultState:NO];
        }
        resultError = (entitlements && entitlements.count > 0) ? nil : error;
      }

      run_block_on_main(completion, entitlements, resultError);
  }];
}

- (void)prepareEntitlementsResultWithCompletion:(QONEntitlementsCompletionHandler)completion {
  if (self.launchError || self.unhandledLogoutAvailable) {
    [self actualizeEntitlements:completion];
    return;
  }

  NSDictionary<NSString *, QONEntitlement *> *entitlements = [self getActualEntitlementsForDefaultState:YES];
  entitlements = entitlements ?: @{};

  BOOL entitlementsAreActual = YES;
  NSDate *currentDate = [NSDate date];
  for (NSString *entitlementId in entitlements) {
    QONEntitlement *value = entitlements[entitlementId];
    if (value.isActive && value.expirationDate != nil && value.expirationDate.timeIntervalSince1970 < currentDate.timeIntervalSince1970) {
      entitlementsAreActual = NO;
      break;
    }
  }

  if (entitlementsAreActual) {
    run_block_on_main(completion, entitlements, nil);
  } else {
    [self actualizeEntitlements:completion];
  }
}

- (void)fireEntitlementsBlocks:(NSArray<QONEntitlementsCompletionHandler> *)blocks result:(NSDictionary<NSString *, QONEntitlement *> *)entitlements error:(NSError *)error {
  for (QONEntitlementsCompletionHandler block in blocks) {
    run_block_on_main(block, entitlements, error);
  }
}

- (void)executeEntitlementsBlocksWithError:(NSError *)error {
  [self.entitlementsBlocksLock lock];
  NSArray<QONEntitlementsCompletionHandler> *blocks = [self.entitlementsBlocks copy];
  [self.entitlementsBlocks removeAllObjects];
  [self.entitlementsBlocksLock unlock];
  if (blocks.count == 0) {
    return;
  }

  if (error) {
    if ([self hasPendingIdentityRequests]) {
      [self fireEntitlementsBlocks:blocks result:@{} error:error];
    } else {
      NSDictionary<NSString *, QONEntitlement *> *cachedEntitlements = [self getActualEntitlementsForDefaultState:NO];
      cachedEntitlements = cachedEntitlements ?: @{};
      [self fireEntitlementsBlocks:blocks result:cachedEntitlements error:error];
    }
  } else {
    [self prepareEntitlementsResultWithCompletion:^(NSDictionary<NSString *,QONEntitlement *> * _Nonnull result, NSError * _Nullable resultError) {
      [self fireEntitlementsBlocks:blocks result:result ?: @{} error:resultError];
    }];
  }
}

- (void)executeUserBlocks {
  [self executeUserBlocksWithError:self.launchError];
}

- (void)executeUserBlocksWithError:(nullable NSError *)resultError {
  [self.userInfoBlocksLock lock];
  NSArray<QONUserInfoCompletionHandler> *blocks = [self.userInfoBlocks copy];
  [self.userInfoBlocks removeAllObjects];
  [self.userInfoBlocksLock unlock];
  if (blocks.count == 0) {
    return;
  }

  [self actualizeUserInfo];
  QONUser *user = self.user;
  for (QONUserInfoCompletionHandler block in blocks) {
    run_block_on_main(block, user, resultError);
  }
}

- (void)executeOfferingsBlocks {
  [self executeOfferingsBlocksWithError:nil];
}

- (void)executeOfferingsBlocksWithError:(NSError * _Nullable)error {
  @synchronized (self) {
    if (self.offeringsBlocks.count == 0) {
      return;
    }
    
    NSArray <QONOfferingsCompletionHandler> *blocks = [self.offeringsBlocks copy];
    
    [self.offeringsBlocks removeAllObjects];
    
    if (error) {
      for (QONOfferingsCompletionHandler block in blocks) {
        run_block_on_main(block, nil, error);
      }
      
      return;
    }
    
    NSError *resultError = error ?: _launchError;
    
    QONOfferings *offerings = [self enrichOfferingsWithStoreProducts];
    resultError = offerings ? nil : resultError;
    
    if (!offerings && !resultError) {
      resultError = [QONErrors emptyOfferingsError];
    }
    
    for (QONOfferingsCompletionHandler block in blocks) {
      run_block_on_main(block, offerings, resultError);
    }
  }
}

- (QONOfferings *)enrichOfferingsWithStoreProducts {
  QONOfferings *offerings = [self getActualOfferings];
  
  for (QONOffering *offering in offerings.availableOfferings) {
    for (QONProduct *product in offering.products) {
      QONProduct *qnProduct = [self productAt:product.qonversionID];
      
      product.skProduct = qnProduct.skProduct;
    }
  }
  
  return offerings;
  
}

- (void)executeProductsBlocks {
  [self executeProductsBlocksWithError:nil];
}

- (void)executeProductsBlocksWithError:(NSError * _Nullable)error {
  @synchronized (self) {
    NSArray <QONProductsCompletionHandler> *_blocks = [self->_productsBlocks copy];
    if (_blocks.count == 0) {
      return;
    }
    
    [_productsBlocks removeAllObjects];
    
    if (error) {
      for (QONProductsCompletionHandler _block in _blocks) {
        run_block_on_main(_block, @{}, error);
      }
      
      return;
    }
    
    NSArray *products = [(_launchResult.products ?: @{}) allValues];
    
    NSError *resultError;
    
    if (self.launchError) {
      // check if the cache is actual, set the products, and reset the error
      NSDictionary<NSString *, QONProduct *> *actualProducts = [self getActualProducts];
      products = actualProducts.allValues.count > 0 ? actualProducts.allValues : products;
      resultError = actualProducts.count > 0 ? nil : self.launchError;
    }
    
    NSDictionary *resultProducts = [self enrichProductsWithStoreProducts:products];
    NSDictionary *result = resultError ? @{} : [resultProducts copy];
    for (QONProductsCompletionHandler _block in _blocks) {
      run_block_on_main(_block, result, resultError);
    }
  }
}

- (NSDictionary<NSString *, QONProduct *> *)enrichProductsWithStoreProducts:(NSArray<QONProduct *> *)products {
  NSMutableDictionary *resultProducts = [[NSMutableDictionary alloc] init];
  for (QONProduct *_product in products) {
    if (!_product.qonversionID) {
      continue;
    }
    
    QONProduct *qnProduct = [self productAt:_product.qonversionID];
    if (qnProduct) {
      [resultProducts setValue:qnProduct forKey:_product.qonversionID];
    }
  }
  
  return [resultProducts copy];
}

- (void)loadProducts {
  if (!self.launchResult || self.productsLoading) {
    return;
  }
  
  self.productsLoading = YES;
  
  NSDictionary<NSString *, QONProduct *> *productsMap = [self getActualProducts];
  NSArray<QONProduct *> *products = productsMap.allValues;
  
  NSMutableSet *productsSet = [[NSMutableSet alloc] init];
  
  if (products) {
    for (QONProduct *product in products) {
      if (product.storeID) {
        [productsSet addObject:product.storeID];
      }
    }
  }

  [_storeKitService loadProducts:productsSet];
}

- (void)products:(QONProductsCompletionHandler)completion {
  @synchronized (self) {
    [self.productsBlocks addObject:completion];
    
    if (self.productsLoading) {
      return;
    }
    
    [self retryLaunchFlowWithTrigger:QONRequestTriggerProducts completion:^{
      [self executeProductsBlocks];
    }];
  }
}

- (void)checkTrialIntroEligibilityForProductIds:(NSArray<NSString *> *)productIds completion:(QONEligibilityCompletionHandler)completion {
  NSArray *uniqueProductIdentifiers = [NSSet setWithArray:productIds].allObjects;
  
  __block __weak QNProductCenterManager *weakSelf = self;
  [self products:^(NSDictionary<NSString *,QONProduct *> * _Nonnull result, NSError * _Nullable error) {
    for (NSString *identifier in uniqueProductIdentifiers) {
      QONProduct *product = result[identifier];
      if (!product) {
        QONVERSION_LOG(@"❌ product with id: %@ not found", identifier);
        run_block_on_main(completion, @{}, [QONErrors errorWithQONErrorCode:QONErrorCodeProductNotFound]);
        return;
      }
    }

    NSArray<QONProduct *> *products = [result.allValues filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(QONProduct *product, NSDictionary *bindings) {
      return product.storeID.length > 0;
    }]];
    
    [weakSelf.apiClient checkTrialIntroEligibilityParamsForProducts:products completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
      QNMapperObject *result = [QNMapper mapperObjectFrom:dict];
      if (result.error) {
        run_block_on_main(completion, @{}, result.error);
        return;
      }
      
      NSDictionary<NSString *, QONIntroEligibility *> *eligibilityData = [QNMapper mapProductsEligibility:result.data];
      NSMutableDictionary<NSString *, QONIntroEligibility *> *resultEligibility = [NSMutableDictionary new];
      
      for (NSString *identifier in uniqueProductIdentifiers) {
        QONIntroEligibility *item = eligibilityData[identifier];
        if (item) {
          resultEligibility[identifier] = item;
        }
      }
      
      run_block_on_main(completion, [resultEligibility copy], nil);
    }];
  }];
}

- (void)retryLaunchFlowWithTrigger:(QONRequestTrigger)requestTrigger completion:(void(^)(void))completion {
  if (self.launchError) {
    __block __weak QNProductCenterManager *weakSelf = self;
    [self launchWithTrigger:requestTrigger completion:^(QONLaunchResult * _Nonnull result, NSError * _Nullable error) {
      if (weakSelf.productsLoading) {
        return;
      } else {
        completion();
      }
    }];
  } else {
    NSArray *storeProducts = [self.storeKitService getLoadedProducts];
    if (storeProducts.count > 0) {
      completion();
      return;
    } else {
      [self loadProducts];
    }
  }
}

- (void)offerings:(QONOfferingsCompletionHandler)completion {
  @synchronized (self) {
    [self.offeringsBlocks addObject:completion];
    
    __block __weak QNProductCenterManager *weakSelf = self;
    QONProductsCompletionHandler productsCompletion = ^(NSDictionary<NSString *, QONProduct *> *result, NSError  *_Nullable error) {
      [weakSelf executeOfferingsBlocksWithError:error];
    };
    
    [self products:productsCompletion];
  }
}

- (QONProduct *)productAt:(NSString *)productID {
  QONProduct *product = [self QNProduct:productID];
  if (product) {
    id skProduct = [_storeKitService productAt:product.storeID];
    if (skProduct) {
      [product setSkProduct:skProduct];
    }
    return product;
  }
  return nil;
}

- (QONProduct * _Nullable)QNProduct:(NSString *)productID {
  NSDictionary *products = [self getActualProducts];
  
  return products[productID];
}

- (void)launch:(QONRequestTrigger)requestTrigger
    completion:(void (^)(QONLaunchResult * _Nullable result, NSError * _Nullable error))completion {
  [self launch:requestTrigger identityRequest:nil completion:completion];
}

- (void)launch:(QONRequestTrigger)requestTrigger
 identityRequest:(nullable QNIdentityRequestData *)identityRequest
    completion:(void (^)(QONLaunchResult * _Nullable result, NSError * _Nullable error))completion {
  [self launch:requestTrigger
identityRequest:identityRequest
expectedIdentityMutationGeneration:nil
 completion:completion];
}

- (void)launch:(QONRequestTrigger)requestTrigger
 identityRequest:(nullable QNIdentityRequestData *)identityRequest
expectedIdentityMutationGeneration:(nullable NSNumber *)expectedGeneration
    completion:(void (^)(QONLaunchResult * _Nullable result, NSError * _Nullable error))completion {
  [self.identityMutationLock lock];
  NSNumber *ownerGeneration = expectedGeneration;
  if (!identityRequest && !ownerGeneration) {
    // Every response that can write user/launch state belongs to the user
    // generation at request start. This prevents an old products/actualize/
    // init response from overwriting state after identify/logout/restore.
    ownerGeneration = @(self.identityMutationGeneration);
  }

  [self.userInfoBlocksLock lock];
  [self.launchStateLock lock];
  self.launchesInFlight += 1;
  self.launchingFinished = NO;
  [self.launchStateLock unlock];
  [self.userInfoBlocksLock unlock];

  __block __weak QNProductCenterManager *weakSelf = self;
  __block BOOL launchTicketReleased = NO;
  void (^releaseLaunchTicket)(NSError * _Nullable) = ^(NSError * _Nullable terminalError) {
    BOOL allLaunchesFinished = NO;
    NSError *errorToDeliver = nil;
    NSArray<QONUserInfoCompletionHandler> *terminalUserBlocks = nil;
    QONUser *terminalUser = nil;
    [weakSelf.identityMutationLock lock];
    [weakSelf.userInfoBlocksLock lock];
    [weakSelf.launchStateLock lock];
    if (!launchTicketReleased) {
      launchTicketReleased = YES;
      // The last finishing launch determines the terminal state seen by work
      // that was waiting for the whole concurrent launch set to become idle.
      weakSelf.pendingLaunchTerminalError = terminalError;
      if (weakSelf.launchesInFlight > 0) {
        weakSelf.launchesInFlight -= 1;
      }
      allLaunchesFinished = weakSelf.launchesInFlight == 0;
      weakSelf.launchingFinished = allLaunchesFinished;
      if (allLaunchesFinished) {
        errorToDeliver = weakSelf.pendingLaunchTerminalError;
        weakSelf.pendingLaunchTerminalError = nil;
      }
    }
    [weakSelf.launchStateLock unlock];

    if (allLaunchesFinished) {
      terminalUserBlocks = [weakSelf.userInfoBlocks copy];
      [weakSelf.userInfoBlocks removeAllObjects];
      [weakSelf actualizeUserInfo];
      terminalUser = weakSelf.user;
    }
    [weakSelf.userInfoBlocksLock unlock];
    [weakSelf.identityMutationLock unlock];

    if (allLaunchesFinished) {
      // launchingFinished and the terminal userInfo snapshot are published
      // atomically with launch start. A new launch cannot enqueue its callback
      // into the ticket that just finished.
      for (QONUserInfoCompletionHandler block in terminalUserBlocks) {
        run_block_on_main(block, terminalUser, errorToDeliver);
      }
      if ([weakSelf isIdentityMutationSupersededError:errorToDeliver]) {
        // A superseded response intentionally skips the normal high-level
        // commit path. Terminate every queue that depended on that launch;
        // otherwise products/offerings can remain retained forever
        // when no replacement launch is required (for example, no-op logout).
        [weakSelf executeProductsBlocksWithError:errorToDeliver];
        [weakSelf executeOfferingsBlocksWithError:errorToDeliver];
      }
      NSNotification *notification = [NSNotification notificationWithName:kLaunchIsFinishedNotification object:weakSelf];
      [[NSNotificationCenter defaultCenter] postNotification:notification];
      [weakSelf handlePendingRequests:errorToDeliver];
    }
  };

  [self.apiClient launchRequest:requestTrigger completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
    __block BOOL mutationLockHeld = NO;
    if (identityRequest || ownerGeneration) {
      [weakSelf.identityMutationLock lock];
      mutationLockHeld = YES;
      if (identityRequest && ![weakSelf isActiveIdentityRequest:identityRequest]) {
        [weakSelf.identityMutationLock unlock];
        mutationLockHeld = NO;
        releaseLaunchTicket([weakSelf identityMutationSupersededError]);
        return;
      }
      if (ownerGeneration && weakSelf.identityMutationGeneration != ownerGeneration.unsignedIntegerValue) {
        NSError *supersededError = [weakSelf identityMutationSupersededError];
        if (completion) {
          completion([[QONLaunchResult alloc] init], supersededError);
        }
        [weakSelf.identityMutationLock unlock];
        releaseLaunchTicket(supersededError);
        return;
      }
    }

    void (^finishLaunch)(QONLaunchResult *, NSError *) = ^(QONLaunchResult *result, NSError *finishError) {
      if (completion) {
        completion(result, finishError);
      }
      if (mutationLockHeld) {
        [weakSelf.identityMutationLock unlock];
        mutationLockHeld = NO;
      }
      releaseLaunchTicket(finishError);
    };
    if (!completion) {
      if (mutationLockHeld) {
        [weakSelf.identityMutationLock unlock];
      }
      releaseLaunchTicket(error);
      return;
    }

    if (error) {
      // Try to parse entitlements from the response even when error is present.
      // This handles cases like Stripe users on iOS where the backend returns
      // valid entitlements (200 OK) but StoreKit throws an error due to empty Apple receipt.
      QONLaunchResult *launchResult = [[QONLaunchResult alloc] init];
      if (dict) {
        QNMapperObject *mappedResult = [QNMapper mapperObjectFrom:dict];
        if (!mappedResult.error && mappedResult.data) {
          launchResult = [QNMapper fillLaunchResult:mappedResult.data];
        }
      }
      finishLaunch(launchResult, error);
      return;
    }

    QNMapperObject *result = [QNMapper mapperObjectFrom:dict];
    if (result.error) {
      finishLaunch([[QONLaunchResult alloc] init], result.error);
      return;
    }

    QONUser *user = [QNMapper fillUser:result.data];
    weakSelf.user = user;

    weakSelf.productsEntitlementsRelation = [QNMapper mapProductsEntitlementsRelation:result.data];
    [weakSelf.persistentStorage storeObject:weakSelf.productsEntitlementsRelation forKey:kKeyQUserDefaultsProductsPermissionsRelation];

    QONLaunchResult *launchResult = [QNMapper fillLaunchResult:result.data];
    finishLaunch(launchResult, nil);
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      [weakSelf.apiClient processStoredRequests];
    });
  }];
  [self.identityMutationLock unlock];
}

- (void)handleFailedTransaction:(SKPaymentTransaction *)transaction forProduct:(SKProduct *)product error:(NSError *)error {
  QONPurchaseResultCompletionHandler _purchasingBlock = _purchasingBlocks[product.productIdentifier];
  
  BOOL isUserCanceled = error.code == QONErrorCodePurchaseCanceled;
  BOOL isPending = error.code == QONErrorCodePurchasePending;

  if (_purchasingBlock) {
    QONPurchaseResult *purchaseResult;
    if (isUserCanceled) {
      purchaseResult = [QONPurchaseResult userCanceled];
    } else if (isPending) {
      purchaseResult = [QONPurchaseResult pending];
    } else {
      purchaseResult = [QONPurchaseResult errorWithError:error];
    }
    run_block_on_main(_purchasingBlock, purchaseResult);
  }
  
  @synchronized (self) {
    [_purchasingBlocks removeObjectForKey:product.productIdentifier];
  }
}

- (void)handlePurchases:(NSArray<QONStoreKit2PurchaseModel *> *)purchasesInfo completion:(QONDefaultCompletionHandler)completion {
  __block __weak QNProductCenterManager *weakSelf = self;
  __block QONDefaultCompletionHandler resultCompletion = [completion copy];
  [self.storeKitService receipt:^(NSString * receipt) {
    for (QONStoreKit2PurchaseModel *purchaseModel in purchasesInfo) {
      __block NSURLRequest *request = [self.apiClient handlePurchase:purchaseModel
                                                             receipt:receipt
                                                      requestTrigger:QONRequestTriggerHandleStoreKit2Transactions
                                                          completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
        BOOL success = error == nil;
        if (error && [QNUtils shouldPurchaseRequestBeRetried:error]) {
          [weakSelf.apiClient storeRequestForRetry:request transactionId:purchaseModel.transactionId];
        } else {
          [weakSelf.apiClient removeStoredRequestForTransactionId:purchaseModel.transactionId];
        }
        
        if (resultCompletion) {
          resultCompletion(success, error);
          resultCompletion = nil;
        }
      }];
    }
  }];
}

// MARK: - QNStoreKitServiceDelegate

- (void)handleRestoredTransactions:(NSArray<SKPaymentTransaction *> *)transactions {
  self.restoredTransactions = [transactions copy];
}

- (void)handleExcessTransactions:(NSArray<SKPaymentTransaction *> *)transactions {
  if (self.launchMode == QONLaunchModeSubscriptionManagement) {
    for (SKPaymentTransaction *transaction in transactions) {
      [self.storeKitService finishTransaction:transaction];
    }
  }
}

- (void)handlePurchasedTransaction:(SKPaymentTransaction *)transaction forProduct:(SKProduct *)product {
  __block __weak QNProductCenterManager *weakSelf = self;
  
  [self.storeKitService receipt:^(NSString * receipt) {
    NSDictionary *allPurchaseOptions = [weakSelf actualPurchaseOptions];
    QONPurchaseOptions *purchaseOptions = allPurchaseOptions[product.productIdentifier];

    QONRequestTrigger requestTrigger = QONRequestTriggerPurchase;
    if (transaction.transactionState == SKPaymentTransactionStateRestored) {
      requestTrigger = QONRequestTriggerSyncHistoricalData;
    }

    __block NSURLRequest *request = [weakSelf.apiClient purchaseRequestWith:product transaction:transaction receipt:receipt purchaseOptions:purchaseOptions requestTrigger:requestTrigger completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
      QONPurchaseResultCompletionHandler _purchasingBlock = weakSelf.purchasingBlocks[product.productIdentifier];
      @synchronized (weakSelf) {
        [weakSelf.purchasingBlocks removeObjectForKey:product.productIdentifier];
      }
      
      [weakSelf removePurchaseOptionsForStoreProductId:product.productIdentifier];
      
      if (transaction.transactionIdentifier != nil) {
        if (error && [QNUtils shouldPurchaseRequestBeRetried:error]) {
          [weakSelf.apiClient storeRequestForRetry:request transactionId:transaction.transactionIdentifier];
        } else {
          [weakSelf.apiClient removeStoredRequestForTransactionId:transaction.transactionIdentifier];
        }
      }

      QNMapperObject *result = [QNMapper mapperObjectFrom:dict];
      NSError *resultError = error ?: result.error;
      
      QONUser *user = [QNMapper fillUser:result.data];
      weakSelf.user = user;
      
      if (weakSelf.launchMode == QONLaunchModeSubscriptionManagement && !resultError) {
        [weakSelf.storeKitService finishTransaction:transaction];
      }
      
      QONLaunchResult *launchResult = [QNMapper fillLaunchResult:result.data];
      
      if (!resultError) {
        @synchronized (weakSelf) {
          weakSelf.launchResult = launchResult;
          weakSelf.launchError = nil;
        }
        
        [weakSelf storeLaunchResultIfNeeded:launchResult];
      }
      
      if (_purchasingBlock) {
        QONPurchaseResult *purchaseResult;
        if (resultError) {
          if ([weakSelf shouldCalculateEntitlementsForError:resultError]) {
            NSDictionary<NSString *, QONEntitlement *> *calculatedEntitlements = [weakSelf calculateEntitlementsForTransactions:@[transaction] products:@[product]];
            purchaseResult = [QONPurchaseResult successFromFallbackWithEntitlements:calculatedEntitlements transaction:transaction];
          } else {
            purchaseResult = [QONPurchaseResult errorWithError:resultError];
          }
        } else {
          purchaseResult = [QONPurchaseResult successWithEntitlements:launchResult.entitlements transaction:transaction];
        }
        run_block_on_main(_purchasingBlock, purchaseResult);
      } else {
        if (transaction.transactionState == SKPaymentTransactionStateRestored) {
          // One successful restored purchase result from API is enough to assume that the receipt is successfully handled by the backend
          if (!resultError) {
            [weakSelf handleRestoreResult:launchResult.entitlements error:nil];
          }
        } else {
          NSDictionary<NSString *, QONEntitlement *> *resultEntitlements = launchResult.entitlements;
          BOOL shouldNotify = NO;
          if (resultError) {
            if ([weakSelf shouldCalculateEntitlementsForError:resultError]) {
              resultEntitlements = [weakSelf calculateEntitlementsForTransactions:@[transaction] products:@[product]];
              shouldNotify = YES;
            }
          } else {
            shouldNotify = YES;
          }
          if (shouldNotify) {
            // Single listener: adapter pattern handles legacy EntitlementsUpdateListener
            QONPurchaseResult *deferredResult = [QONPurchaseResult successWithEntitlements:resultEntitlements transaction:transaction];
            [weakSelf.deferredPurchasesListener deferredPurchaseCompleted:deferredResult];
          }
        }
      }
    }];
  }];
}

- (BOOL)shouldCalculateEntitlementsForError:(NSError *)error {
  return (error.code >= kInternalServerErrorFirstCode && error.code <= kInternalServerErrorLastCode) || [QNUtils isConnectionError:error];
}

- (void)handleRestoreResult:(NSDictionary<NSString *, QONEntitlement *> *)entitlements error:(NSError *)error {
  if (!self.awaitingRestoreResult) {
    return;
  }
  self.awaitingRestoreResult = NO;
  
  self.restoredTransactions = nil;
  
  [self executeRestoreBlocksWithResult:entitlements error:error];
}

- (void)handleRestoreCompletedTransactionsFinished {
  if (!self.awaitingRestoreResult) {
    return;
  }
  self.awaitingRestoreResult = NO;

  NSArray *restoredTransactionsCopy = [self.restoredTransactions copy];
  self.restoredTransactions = nil;
  __block __weak QNProductCenterManager *weakSelf = self;
  [self.identityMutationLock lock];
  NSUInteger ownerGeneration = self.transactionsRestoreIdentityMutationGeneration;
  if (self.identityMutationGeneration != ownerGeneration) {
    NSError *supersededError = [self identityMutationSupersededError];
    [self.identityMutationLock unlock];
    [self executeRestoreBlocksWithResult:@{} error:supersededError];
    return;
  }
  [self launch:QONRequestTriggerSyncHistoricalData
identityRequest:nil
expectedIdentityMutationGeneration:@(ownerGeneration)
 completion:^(QONLaunchResult * _Nonnull result, NSError * _Nullable error) {
    if (error) {
      if ([weakSelf isIdentityMutationSupersededError:error]) {
        [weakSelf executeRestoreBlocksWithResult:@{} error:error];
      } else if ([weakSelf shouldCalculateEntitlementsForError:error]) {
        NSArray<SKProduct *> *storeProducts = [weakSelf.storeKitService getLoadedProducts];
        NSDictionary<NSString *, QONEntitlement *> *calculatedEntitlements = [weakSelf calculateEntitlementsForRestoredTransactions:restoredTransactionsCopy products:storeProducts];

        [weakSelf executeRestoreBlocksWithResult:calculatedEntitlements error:nil];
      } else {
        [weakSelf executeRestoreBlocksWithResult:@{} error:error];
      }
    } else if (result) {
      [weakSelf handleUserSwitchIfNeededWithResult:result];
      [weakSelf storeLaunchResultIfNeeded:result];
      weakSelf.launchResult = result;
      [weakSelf executeRestoreBlocksWithResult:result.entitlements error:error];
    }
  }];
  [self.identityMutationLock unlock];
}

- (void)handleRestoreCompletedTransactionsFailed:(NSError *)error {
  self.awaitingRestoreResult = NO;
  [self executeRestoreBlocksWithResult:@{} error:error];
}

- (void)executeRestoreBlocksWithResult:(NSDictionary<NSString *, QONEntitlement *> *)entitlements error:(NSError *)error {
  [self.restoreBlocksLock lock];
  self.restoreInProgress = NO;
  NSArray<QNRestoreCompletionHandler> *blocks = [self.restorePurchasesBlocks copy];
  [self.restorePurchasesBlocks removeAllObjects];
  [self.restoreBlocksLock unlock];

  NSDictionary<NSString *, QONEntitlement *> *resultEntitlements = entitlements ?: @{};
  for (QNRestoreCompletionHandler block in blocks) {
    dispatch_async(dispatch_get_main_queue(), ^{
      block(resultEntitlements, error);
    });
  }

  [self handlePendingRequests:error];
}

- (void)getPromotionalOfferForProduct:(QONProduct *)product
                             discount:(SKProductDiscount *)discount
                           completion:(QONPromotionalOfferCompletionHandler)completion {
  __block __weak QNProductCenterManager *weakSelf = self;
  [self.storeKitService receipt:^(NSString * receipt) {
    NSString *identityId = [weakSelf.userInfoService obtainCustomIdentityUserID];
    NSString *userId = [weakSelf.userInfoService obtainUserID];
    
    [self.apiClient getPromotionalOfferForProduct:product discount:discount userId:userId identityId:identityId receipt:receipt completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
      if (error) {
        run_block_on_main(completion, nil, error);
        return;
      } else {
        NSError *mappingError;
        QONPromotionalOffer *promoOffer = [QNMapper mapPromoOffer:dict productDiscount:discount mappingError:&mappingError];
        if (!promoOffer) {
          run_block_on_main(completion, nil, mappingError);
          return;
        }
        
        run_block_on_main(completion, promoOffer, nil);
      }
    }];
  }];
}

- (void)handleProducts:(NSArray<SKProduct *> *)products {
  @synchronized (self) {
    self->_productsLoading = NO;
  }
  
  [self executeProductsBlocks];
}

- (void)handleProductsRequestFailed:(NSError *)error {
  @synchronized (self) {
    self->_productsLoading = NO;
  }
  
  NSError *er = [QONErrors errorFromTransactionError:error];
  QONVERSION_LOG(@"⚠️ Store products request failed with message: %@", er.description);
  [self executeProductsBlocksWithError:error];
}

- (void)handleDeferredTransaction:(SKPaymentTransaction *)transaction forProduct:(SKProduct *)product {
  NSError *error = [QONErrors deferredTransactionError];
  
  [self handleFailedTransaction:transaction forProduct:product error:error];
}

- (void)handleFailedTransaction:(SKPaymentTransaction *)transaction forProduct:(SKProduct *)product {
  NSError *error = [QONErrors errorFromTransactionError:transaction.error];
  
  [self handleFailedTransaction:transaction forProduct:product error:error];
}

- (BOOL)paymentQueue:(SKPaymentQueue *)queue shouldAddStorePayment:(SKPayment *)payment forProduct:(SKProduct *)product {
  __block __weak QNProductCenterManager *weakSelf = self;
  
  if ([self.promoPurchasesDelegate respondsToSelector:@selector(shouldPurchasePromoProductWithIdentifier:executionBlock:)]) {
    [self.promoPurchasesDelegate shouldPurchasePromoProductWithIdentifier:product.productIdentifier executionBlock:^(QONPurchaseCompletionHandler _Nonnull completion) {
      // Convert legacy completion to PurchaseResult completion
      void(^resultCompletion)(QONPurchaseResult *) = ^(QONPurchaseResult *result) {
        if (completion) {
          if (result.isSuccessful) {
            run_block_on_main(completion, result.entitlements ?: @{}, nil, NO);
          } else if (result.isCanceledByUser) {
            run_block_on_main(completion, @{}, nil, YES);
          } else if (result.isPending) {
            NSError *pendingError = [QONErrors errorWithQONErrorCode:QONErrorCodePurchasePending];
            run_block_on_main(completion, @{}, pendingError, NO);
          } else {
            NSError *error = result.error ?: [QONErrors errorWithQONErrorCode:QONErrorCodeUnknown];
            run_block_on_main(completion, @{}, error, NO);
          }
        }
      };
      
      weakSelf.purchasingBlocks[product.productIdentifier] = resultCompletion;
      
      [weakSelf.storeKitService purchaseProduct:product];
    }];
    
    return NO;
  }
  
  return YES;
}

- (void)storeEntitlements:(NSDictionary<NSString *, QONEntitlement *> *)entitlements {
  self.entitlements = entitlements;
  NSDate *currentDate = [NSDate date];
  
  [self.persistentStorage storeDouble:currentDate.timeIntervalSince1970 forKey:kKeyQUserDefaultsPermissionsTimestamp];
  [self.persistentStorage storeObject:entitlements forKey:kKeyQUserDefaultsPermissions];
}

- (NSDictionary<NSString *, QONEntitlement *> * _Nullable)getActualEntitlementsForDefaultState:(BOOL)defaultState {
  if (self.entitlements) {
    return self.entitlements;
  }
  
  NSDictionary<NSString *, QONEntitlement *> *entitlements = [self.persistentStorage loadObjectForKey:kKeyQUserDefaultsPermissions];
  NSTimeInterval cachedPermissionsTimestamp = [self cachedPermissionsTimestamp];
  BOOL isCacheOutdated = [QNUtils isPermissionsOutdatedForDefaultState:defaultState cacheDataTimeInterval:cachedPermissionsTimestamp cacheLifetime:self.cacheLifetime];

  if (!isCacheOutdated) {
    self.entitlements = entitlements;
  }
  
  return self.entitlements;
}

- (NSTimeInterval)cachedPermissionsTimestamp {
  return [self.persistentStorage loadDoubleForKey:kKeyQUserDefaultsPermissionsTimestamp];
}

- (void)resetActualPermissionsCache {
  self.entitlements = nil;
  [self.persistentStorage removeObjectForKey:kKeyQUserDefaultsPermissions];
  [self.persistentStorage removeObjectForKey:kKeyQUserDefaultsPermissionsTimestamp];
}

- (void)handleUserSwitchIfNeededWithResult:(QONLaunchResult *)result {
  if (!result) {
    return;
  }

  [self.identityMutationLock lock];
  // A valid restore response claims this generation even when the receipt
  // belongs to the current uid. Only the first response accepted against a
  // generation may update global launch/user state; sibling restores become
  // stale before they can publish a different scope.
  self.identityMutationGeneration += 1;
  if (result.uid.length == 0) {
    [self.identityMutationLock unlock];
    return;
  }
  NSString *currentUserID = [self.userInfoService obtainUserID];
  if ([currentUserID isEqualToString:result.uid]) {
    [self.identityMutationLock unlock];
    return;
  }

  QONVERSION_LOG(@"🔄 Restore: user switch detected from %@ to %@", currentUserID, result.uid);

  [self.userInfoService storeIdentity:result.uid];
  [self.remoteConfigManager userHasBeenChangedToUserID:result.uid];
  [self resetActualPermissionsCache];
  [self.identityMutationLock unlock];
}

// MARK: - Move to separate file

- (void)handlePurchaseResult:(NSDictionary<NSString *, QONEntitlement *> *)result
                       error:(NSError *)error
                   cancelled:(BOOL)cancelled
                 transaction:(SKPaymentTransaction *)transaction
                     product:(SKProduct *)product
                  completion:(QONPurchaseCompletionHandler)completion {
  if (error) {
    if ([self shouldCalculateEntitlementsForError:error]) {
      NSDictionary<NSString *, QONEntitlement *> *calculatedEntitlements = [self calculateEntitlementsForTransactions:@[transaction] products:@[product]];
      run_block_on_main(completion, calculatedEntitlements, nil, cancelled);
    } else {
      run_block_on_main(completion, @{}, error, cancelled);
    }
  } else {
    run_block_on_main(completion, result, nil, cancelled);
  }
}

- (NSDictionary<NSString *, QONEntitlement *> *)calculateEntitlementsForRestoredTransactions:(NSArray<SKPaymentTransaction *> *)transactions
                                                                                 products:(NSArray<SKProduct *> *)products {
  NSSortDescriptor *dateDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"transactionDate" ascending:NO];
  NSArray *sortDescriptors = [NSArray arrayWithObject:dateDescriptor];
  NSArray *sortedTransactions = [transactions sortedArrayUsingDescriptors:sortDescriptors];

  NSMutableDictionary *resultTransactionsDict = [NSMutableDictionary new];
  for (SKPaymentTransaction *transaction in sortedTransactions) {
    if (resultTransactionsDict[transaction.payment.productIdentifier] == nil) {
      resultTransactionsDict[transaction.payment.productIdentifier] = transaction;
    }
  }

  return [self calculateEntitlementsForTransactions:resultTransactionsDict.allValues products:products];
}

- (NSDictionary<NSString *, QONEntitlement *> *)calculateEntitlementsForTransactions:(NSArray<SKPaymentTransaction *> *)transactions
                                                                            products:(NSArray<SKProduct *> *)products {
  NSMutableDictionary<NSString *, QONEntitlement *> *resultEntitlements = [NSMutableDictionary new];
  NSMutableDictionary<NSString *, SKProduct *> *productsMap = [NSMutableDictionary new];

  for (SKProduct *product in products) {
    productsMap[product.productIdentifier] = product;
  }

  NSMutableDictionary<NSString *, QONProduct *> *qonversionProductsMap = [NSMutableDictionary new];
  NSDictionary<NSString *, QONProduct *> *qonversionProducts = self.launchError ? [self getActualProducts] : self.launchResult.products;
  for (QONProduct *value in qonversionProducts.allValues) {
    if (value.storeID.length > 0) {
      qonversionProductsMap[value.storeID] = value;
    }
  }

  if (@available(iOS 11.2, macOS 10.13.2, watchOS 6.2, tvOS 11.2, *)) {
    for (SKPaymentTransaction *transaction in transactions) {
      SKProduct *product = productsMap[transaction.payment.productIdentifier];
      NSDate *expirationDate = [QNUtils calculateExpirationDateForPeriod:product.subscriptionPeriod fromDate:transaction.transactionDate];
      if (!expirationDate || [expirationDate compare:[NSDate date]] == NSOrderedDescending) {
        NSDictionary<NSString *, QONEntitlement *> *entitlements = [self createEntitlementsForProductsMap:qonversionProductsMap transaction:transaction expirationDate:expirationDate];

        [resultEntitlements addEntriesFromDictionary:entitlements];
      }
    }
  } else {
    for (SKPaymentTransaction *transaction in transactions) {
      QONProduct *qonversionProduct = qonversionProductsMap[transaction.payment.productIdentifier];
      NSDate *expirationDate = [QNUtils calculateExpirationDateForProduct:qonversionProduct fromDate:transaction.transactionDate];
      if (!expirationDate || [expirationDate compare:[NSDate date]] == NSOrderedDescending) {
        NSDictionary<NSString *, QONEntitlement *> *entitlements = [self createEntitlementsForProductsMap:qonversionProductsMap transaction:transaction expirationDate:expirationDate];

        [resultEntitlements addEntriesFromDictionary:entitlements];
      }
    }
  }

  resultEntitlements = [self mergeEntitlements:resultEntitlements];
  
  NSDictionary<NSString *, QONEntitlement *> *resultEntitlementsCopy = [resultEntitlements copy];

  [self storeEntitlements:resultEntitlementsCopy];

  return resultEntitlementsCopy;
}

- (NSMutableDictionary<NSString *, QONEntitlement *> *)mergeEntitlements:(NSMutableDictionary *)entitlements {
  NSDictionary *currentEntitlements = [self getActualEntitlementsForDefaultState:NO];
  NSMutableDictionary<NSString *, QONEntitlement *> *resultEntitlements = currentEntitlements ? [currentEntitlements mutableCopy] : [NSMutableDictionary new];

  for (QONEntitlement *entitlement in entitlements.allValues) {
    QONEntitlement *currentEntitlement = resultEntitlements[entitlement.entitlementID];
    if (!currentEntitlement || !currentEntitlement.isActive || [entitlement.expirationDate compare:currentEntitlement.expirationDate] == NSOrderedDescending) {
      resultEntitlements[entitlement.entitlementID] = entitlement;
    }
  }

  return resultEntitlements;
}

- (NSDictionary<NSString *, QONEntitlement *> *)createEntitlementsForProductsMap:(NSDictionary *)productsMap
                                                                     transaction:(SKPaymentTransaction *)transaction
                                                                  expirationDate:(NSDate *)expirationDate {
  NSMutableDictionary<NSString *, QONEntitlement *> *resultEntitlements = [NSMutableDictionary new];

  QONProduct *qonversionProduct = productsMap[transaction.payment.productIdentifier];
  
  if (self.productsEntitlementsRelation.count == 0) {
    [self actualizeFallbackData];
    self.productsEntitlementsRelation = self.fallbackData.productsEntitlementsRelation;
  }

  NSArray<NSString *> *entitlementsIds = self.productsEntitlementsRelation[qonversionProduct.qonversionID];
  for (NSString *entitlementId in entitlementsIds) {
    QONEntitlement *entitlement = [self createEntitlementsForId:entitlementId qonversionProduct:qonversionProduct transaction:transaction expirationDate:expirationDate];

    resultEntitlements[entitlement.entitlementID] = entitlement;
  }

  return [resultEntitlements copy];
}

- (QONEntitlement *)createEntitlementsForId:(NSString *)entitlementId
                       qonversionProduct:(QONProduct *)qonversionProduct
                             transaction:(SKPaymentTransaction *)transaction
                          expirationDate:(NSDate *)expirationDate {
  QONEntitlement *entitlement = [[QONEntitlement alloc] init];
  entitlement.entitlementID = entitlementId;
  entitlement.isActive = YES;
  entitlement.renewState = QONEntitlementRenewStateUnknown;
  entitlement.source = QONEntitlementSourceAppStore;
  entitlement.productID = qonversionProduct.qonversionID;
  entitlement.startedDate = transaction.transactionDate;
  entitlement.expirationDate = expirationDate;
  entitlement.transactions = @[];

  return entitlement;
}

- (void)actualizeUserInfo {
  NSString *qonversionId = [self.userInfoService obtainUserID];
  NSString *identityId = [self.userInfoService obtainCustomIdentityUserID];

  QONUser *actualUser = [[QONUser alloc] initWithID:qonversionId originalAppVersion:self.user.originalAppVersion identityId:identityId ];
  
  self.user = actualUser;
}

- (void)handlePendingRequests:(NSError *)lastError {
  [self.identityMutationLock lock];
  if (!self.launchingFinished || self.restoreInProgress) {
    [self.identityMutationLock unlock];
    return;
  }

  QNIdentityRequestData *requestToStart = nil;
  [self.identityStateLock lock];
  if (self.activeIdentityRequest || self.identityLogoutInProgress) {
    [self.identityStateLock unlock];
    [self.identityMutationLock unlock];
    return;
  }
  requestToStart = [self takeNextIdentityRequestIfReadyLocked];
  BOOL identityWorkBecameActive = self.activeIdentityRequest != nil || self.pendingIdentityRequests.count > 0;
  [self.identityStateLock unlock];
  if (requestToStart) {
    [self startIdentityRequest:requestToStart];
  } else if (identityWorkBecameActive) {
    [self.identityMutationLock unlock];
    return;
  } else if (self.unhandledLogoutAvailable) {
    [self handleLogout];
  } else {
    [self.remoteConfigManager handlePendingRequests];
    [self executeEntitlementsBlocksWithError:lastError];
  }
  [self.identityMutationLock unlock];
}

- (BOOL)hasPendingIdentityRequests {
  [self.identityStateLock lock];
  BOOL hasRequests = self.activeIdentityRequest != nil || self.pendingIdentityRequests.count > 0;
  [self.identityStateLock unlock];
  return hasRequests;
}

- (nullable QNIdentityRequestData *)takeNextIdentityRequestIfReadyLocked {
  if (self.activeIdentityRequest || self.identityLogoutInProgress || !self.launchingFinished || self.restoreInProgress || self.pendingIdentityRequests.count == 0) {
    return nil;
  }
  QNIdentityRequestData *request = self.pendingIdentityRequests.firstObject;
  [self.pendingIdentityRequests removeObjectAtIndex:0];
  self.activeIdentityRequest = request;
  self.identityInProgress = YES;
  return request;
}

- (BOOL)isActiveIdentityRequest:(QNIdentityRequestData *)request {
  [self.identityStateLock lock];
  BOOL isActive = self.activeIdentityRequest == request;
  [self.identityStateLock unlock];
  return isActive;
}

- (void)startIdentityRequest:(nullable QNIdentityRequestData *)request {
  if (!request || ![self isActiveIdentityRequest:request]) {
    return;
  }

  NSString *identityID = request.identityID;
  NSString *currentIdentityID = [self.userInfoService obtainCustomIdentityUserID];
  if ([currentIdentityID isEqualToString:identityID]) {
    [self finishIdentityRequest:request error:nil];
    return;
  }

  // Clear the previous terminal-error latch before any network work for this
  // identity begins. identityInProgress is already true, so Remote Config
  // cannot observe a stable old scope between serialized attempts.
  [self.remoteConfigManager userChangingRequestStarted];
  if (![self isActiveIdentityRequest:request]) {
    return;
  }

  __block __weak QNProductCenterManager *weakSelf = self;
  if (self.launchError) {
    [self launch:QONRequestTriggerIdentify identityRequest:request completion:^(QONLaunchResult * _Nullable result, NSError * _Nullable error) {
      if (![weakSelf isActiveIdentityRequest:request]) {
        return;
      }
      if (error) {
        [weakSelf failIdentityRequest:request error:error];
      } else {
        [weakSelf processIdentity:identityID request:request];
      }
    }];
  } else {
    [self processIdentity:identityID request:request];
  }
}

- (void)failIdentityRequest:(nullable QNIdentityRequestData *)request error:(NSError *)error {
  BOOL mutationLockHeld = NO;
  if (request) {
    [self.identityMutationLock lock];
    mutationLockHeld = YES;
    if (![self isActiveIdentityRequest:request]) {
      [self.identityMutationLock unlock];
      return;
    }
  }
  [self executeEntitlementsBlocksWithError:error];
  [self.remoteConfigManager userChangingRequestFailedWithError:error];
  [self finishIdentityRequest:request error:error];
  if (mutationLockHeld) {
    [self.identityMutationLock unlock];
  }
}

- (void)finishIdentityRequest:(nullable QNIdentityRequestData *)request error:(nullable NSError *)error {
  if (!request) {
    // Retained for focused tests of processIdentity:. Public identify always
    // owns a request record and therefore takes the guarded path below.
    self.identityInProgress = NO;
    [self handlePendingRequests:error];
    return;
  }

  [self.identityStateLock lock];
  if (self.activeIdentityRequest != request) {
    [self.identityStateLock unlock];
    return;
  }
  self.activeIdentityRequest = nil;
  self.identityInProgress = NO;
  [self.identityStateLock unlock];

  [self deliverIdentityRequest:request error:error];
  [self handlePendingRequests:error];
}

- (void)deliverIdentityRequest:(QNIdentityRequestData *)request error:(nullable NSError *)error {
  NSArray<QONUserInfoCompletionHandler> *completions = [request.completions copy];
  [request.completions removeAllObjects];
  if (completions.count == 0) {
    return;
  }
  if (error) {
    for (QONUserInfoCompletionHandler completion in completions) {
      run_block_on_main(completion, nil, error);
    }
    return;
  }
  [self userInfo:^(QONUser * _Nullable user, NSError * _Nullable userInfoError) {
    for (QONUserInfoCompletionHandler completion in completions) {
      run_block_on_main(completion, user, userInfoError);
    }
  }];
}


@end
