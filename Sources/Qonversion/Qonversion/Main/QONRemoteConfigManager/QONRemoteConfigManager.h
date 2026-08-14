//
//  QONRemoteConfigManager.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 21.03.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QONLaunchResult.h"
#import "QONExperiment.h"

@class QONRemoteConfigService, QNProductCenterManager, QNUserPropertiesManager, QONFallbackService;
@protocol QNLocalStorage;

NS_ASSUME_NONNULL_BEGIN

// Internal diagnostic contract. It intentionally lives outside the public
// headers so durable fallback observability can evolve without changing the
// customer-facing Remote Config model.
typedef NS_ENUM(NSInteger, QONRemoteConfigDeliveryOrigin) {
  QONRemoteConfigDeliveryOriginUnknown = 0,
  QONRemoteConfigDeliveryOriginServer = 1,
  QONRemoteConfigDeliveryOriginMemory = 2,
  QONRemoteConfigDeliveryOriginRetryBaseline = 3,
  QONRemoteConfigDeliveryOriginDiskLastKnownGood = 4,
  QONRemoteConfigDeliveryOriginBundle = 5,
};

@interface QONRemoteConfigManager : NSObject

@property (nonatomic, strong) QONRemoteConfigService *remoteConfigService;
@property (nonatomic, strong) QONFallbackService *fallbackService;
@property (nonatomic, strong) QNProductCenterManager *productCenterManager;
@property (nonatomic, strong) QNUserPropertiesManager *userPropertiesManager;
@property (atomic, assign, readonly) QONRemoteConfigDeliveryOrigin lastDeliveryOrigin;

- (instancetype)initWithLocalStorage:(nullable id<QNLocalStorage>)localStorage;

- (void)userChangingRequestStarted;
- (void)userChangingRequestFailedWithError:(NSError *)error;
- (void)handlePendingRequests;
- (void)obtainRemoteConfigWithContextKey:(NSString * _Nullable)contextKey completion:(QONRemoteConfigCompletionHandler)completion;
- (void)obtainRemoteConfigListWithContextKeys:(NSArray<NSString *> *)contextKeys includeEmptyContextKey:(BOOL)includeEmptyContextKey completion:(QONRemoteConfigListCompletionHandler)completion;
- (void)obtainRemoteConfigList:(QONRemoteConfigListCompletionHandler)completion;
- (void)attachUserToExperiment:(NSString *)experimentId groupId:(NSString *)groupId completion:(QONExperimentAttachCompletionHandler)completion;
- (void)detachUserFromExperiment:(NSString *)experimentId completion:(QONExperimentAttachCompletionHandler)completion;
- (void)attachUserToRemoteConfiguration:(NSString *)remoteConfigurationId completion:(QONRemoteConfigurationAttachCompletionHandler)completion;
- (void)detachUserFromRemoteConfiguration:(NSString *)remoteConfigurationId completion:(QONRemoteConfigurationAttachCompletionHandler)completion;
- (void)userHasBeenChanged;
- (void)userHasBeenChangedToUserID:(NSString *)userID;

/**
 Marks every cached remote config stale so the next load fetches a fresh
 targeting evaluation. Non-destructive: loading states and pending completions
 survive; the cache generation bump keeps in-flight loads from re-caching a
 superseded response and re-issues an awaited in-flight load once
 (DEV-1236 B4). Synchronously joins the manager's serial state executor, which
 preserves ordering with handlePendingRequests and identity changes.
 */
- (void)invalidateRemoteConfigsCache;

@end

NS_ASSUME_NONNULL_END
