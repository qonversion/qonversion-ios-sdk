#import <Foundation/Foundation.h>

@class QONRemoteConfigV2Scope, QONRemoteConfigV2State;
@protocol QNLocalStorage;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const QONRemoteConfigV2StorageKey;
FOUNDATION_EXPORT NSUInteger const QONRemoteConfigV2MaximumPersistedScopes;

typedef NS_ENUM(NSInteger, QONRemoteConfigV2StoreLoadStatus) {
  QONRemoteConfigV2StoreLoadStatusFound,
  QONRemoteConfigV2StoreLoadStatusMissing,
  QONRemoteConfigV2StoreLoadStatusFailed,
};

@interface QONRemoteConfigV2Store : NSObject

- (instancetype)init NS_UNAVAILABLE;
/** Test seam and compatibility adapter. A write succeeds only after exact read-back verification. */
- (instancetype)initWithLocalStorage:(id<QNLocalStorage>)localStorage NS_DESIGNATED_INITIALIZER;
/** Durable store using one bounded binary-plist envelope and NSDataWritingAtomic. */
- (instancetype)initWithFileURL:(NSURL *)fileURL NS_DESIGNATED_INITIALIZER;
+ (nullable instancetype)applicationSupportStore;
- (nullable QONRemoteConfigV2State *)stateForScope:(QONRemoteConfigV2Scope *)scope;
- (QONRemoteConfigV2StoreLoadStatus)loadStateForScope:(QONRemoteConfigV2Scope *)scope
                                                state:(QONRemoteConfigV2State * _Nullable * _Nullable)state;
- (BOOL)saveState:(QONRemoteConfigV2State *)state forScope:(QONRemoteConfigV2Scope *)scope;

@end

NS_ASSUME_NONNULL_END
