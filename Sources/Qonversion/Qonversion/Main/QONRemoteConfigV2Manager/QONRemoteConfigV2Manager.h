#import <Foundation/Foundation.h>
#import "QONRemoteConfigSnapshot.h"
#import "QONRemoteConfigUpdate.h"

@class QONRemoteConfigV2AdmissionToken, QONRemoteConfigV2EnvelopeExpectation;
@class QONRemoteConfigV2Release, QONRemoteConfigV2Scope, QONRemoteConfigV2Store;
@protocol QONRemoteConfigV2EnvelopeDecoding;

NS_ASSUME_NONNULL_BEGIN

typedef void (^QONRemoteConfigV2UpdateObserver)(QONRemoteConfigUpdate *update);

typedef NS_ENUM(NSInteger, QONRemoteConfigV2TransitionStatus) {
  QONRemoteConfigV2TransitionStatusAccepted,
  QONRemoteConfigV2TransitionStatusActivated,
  QONRemoteConfigV2TransitionStatusIgnored,
  QONRemoteConfigV2TransitionStatusPersistenceFailed,
  QONRemoteConfigV2TransitionStatusRejected,
  QONRemoteConfigV2TransitionStatusUnchanged,
};

/** Opaque, single-request capability. Tokens are valid only for the manager that issued them. */
@interface QONRemoteConfigV2AdmissionToken : NSObject
- (instancetype)init NS_UNAVAILABLE;
@end

@interface QONRemoteConfigV2Manager : NSObject

@property (nonatomic, strong, readonly) QONRemoteConfigSnapshot *currentSnapshot;
@property (nonatomic, strong, nullable, readonly) QONRemoteConfigSnapshot *lastFetchedSnapshot;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithStore:(QONRemoteConfigV2Store *)store
               fallbackRelease:(nullable QONRemoteConfigV2Release *)fallbackRelease
             fallbackProjectKey:(nullable NSString *)fallbackProjectKey
            fallbackEnvironment:(nullable NSString *)fallbackEnvironment;
- (instancetype)initWithStore:(QONRemoteConfigV2Store *)store
               fallbackRelease:(nullable QONRemoteConfigV2Release *)fallbackRelease
             fallbackProjectKey:(nullable NSString *)fallbackProjectKey
            fallbackEnvironment:(nullable NSString *)fallbackEnvironment
                 envelopeDecoder:(id<QONRemoteConfigV2EnvelopeDecoding>)envelopeDecoder;
/** Internal deterministic-test seam. callbackExecutor must be serial. */
- (instancetype)initWithStore:(QONRemoteConfigV2Store *)store
               fallbackRelease:(nullable QONRemoteConfigV2Release *)fallbackRelease
             fallbackProjectKey:(nullable NSString *)fallbackProjectKey
            fallbackEnvironment:(nullable NSString *)fallbackEnvironment
                 envelopeDecoder:(id<QONRemoteConfigV2EnvelopeDecoding>)envelopeDecoder
                callbackExecutor:(dispatch_queue_t)callbackExecutor NS_DESIGNATED_INITIALIZER;
/**
 Changes current scope and generation synchronously on the state queue without
 waiting for the callback executor. Queued or not-yet-claimed old-generation
 callbacks are cancelled. A callback atomically claimed before this boundary
 may finish after the method returns. No observer runs under an SDK lock.
 */
- (void)setScope:(nullable QONRemoteConfigV2Scope *)scope;
- (nullable QONRemoteConfigV2AdmissionToken *)beginAdmissionForScope:(QONRemoteConfigV2Scope *)scope
                                                        expectation:(QONRemoteConfigV2EnvelopeExpectation *)expectation;
- (QONRemoteConfigV2TransitionStatus)admitBody:(NSData *)body
                                   strongETag:(NSString *)strongETag
                               admissionToken:(QONRemoteConfigV2AdmissionToken *)admissionToken;
- (void)acceptFetchedRelease:(QONRemoteConfigV2Release *)release
                     forScope:(QONRemoteConfigV2Scope *)scope;
- (BOOL)activate;
/** Observer callbacks use the serial main executor by default. */
- (id)addUpdateObserver:(QONRemoteConfigV2UpdateObserver)observer;
- (void)removeUpdateObserver:(id)token;

@end

NS_ASSUME_NONNULL_END
