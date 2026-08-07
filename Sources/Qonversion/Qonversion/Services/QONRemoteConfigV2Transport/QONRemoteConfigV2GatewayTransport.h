#import <Foundation/Foundation.h>
#import "QONRemoteConfigV2ActivationAck.h"
#import "QONRemoteConfigV2FetchCoordinator.h"
#import "QONRemoteConfigV2DeviceInstallDate.h"
#import "QONRemoteConfigV2GatewaySessionStore.h"
#import "QONRemoteConfigV2ProjectIdentityStore.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const QONRemoteConfigV2GatewaySessionPath;
FOUNDATION_EXPORT NSString *const QONRemoteConfigV2GatewaySnapshotPath;
FOUNDATION_EXPORT NSString *const QONRemoteConfigV2GatewayAckPath;
FOUNDATION_EXPORT NSString *const QONRemoteConfigV2GatewaySessionHeader;
FOUNDATION_EXPORT NSUInteger const QONRemoteConfigV2GatewayMaximumBootstrapBytes;

#pragma mark - Client context

/** Exactly the client_context the dark gateway snapshot route accepts. */
@interface QONRemoteConfigV2ClientContext : NSObject <NSCopying>
@property (nonatomic, copy, readonly) NSString *platform;
@property (nonatomic, copy, readonly) NSString *appVersion;
@property (nonatomic, copy, readonly) NSString *osVersion;
@property (nonatomic, copy, readonly) NSString *sdkVersion;
@property (nonatomic, copy, readonly) NSString *locale;
@property (nonatomic, copy, readonly) NSString *deviceModel;
/** Device fact in whole seconds since the epoch; omitted from the body when nil. */
@property (nonatomic, strong, nullable, readonly) NSNumber *deviceInstalledAtSeconds;
- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithPlatform:(NSString *)platform
                               appVersion:(NSString *)appVersion
                                osVersion:(NSString *)osVersion
                               sdkVersion:(NSString *)sdkVersion
                                   locale:(NSString *)locale
                              deviceModel:(NSString *)deviceModel
                 deviceInstalledAtSeconds:(nullable NSNumber *)deviceInstalledAtSeconds
    NS_DESIGNATED_INITIALIZER;
- (nullable NSDictionary<NSString *, id> *)JSONObject;
@end

@protocol QONRemoteConfigV2ClientContextProviding <NSObject>
- (nullable QONRemoteConfigV2ClientContext *)currentClientContext;
@end

/**
 Combines static device facts with the device-scoped install date, so the install
 date reported to the gateway can never be rebound to an identity.
 */
@interface QONRemoteConfigV2DeviceClientContextProvider : NSObject <QONRemoteConfigV2ClientContextProviding>
- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithPlatform:(NSString *)platform
                               appVersion:(NSString *)appVersion
                                osVersion:(NSString *)osVersion
                               sdkVersion:(NSString *)sdkVersion
                                   locale:(NSString *)locale
                              deviceModel:(NSString *)deviceModel
                      installDateProvider:(id<QONRemoteConfigV2DeviceInstallDateProviding>)installDateProvider
    NS_DESIGNATED_INITIALIZER;
@end

#pragma mark - HTTP seam

typedef void (^QONRemoteConfigV2HTTPCompletion)(NSData *_Nullable body,
                                                NSHTTPURLResponse *_Nullable response,
                                                NSError *_Nullable error);

/** The only networking seam of the adapter; tests substitute it wholesale. */
@protocol QONRemoteConfigV2HTTPExecuting <NSObject>
- (void)executeRequest:(NSURLRequest *)request
            completion:(QONRemoteConfigV2HTTPCompletion)completion;
@end

@interface QONRemoteConfigV2URLSessionHTTPExecutor : NSObject <QONRemoteConfigV2HTTPExecuting>
- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithSession:(NSURLSession *)session NS_DESIGNATED_INITIALIZER;
@end

#pragma mark - Typed failures

typedef NS_ENUM(NSInteger, QONRemoteConfigV2TransportFailureKind) {
  QONRemoteConfigV2TransportFailureKindNotConfigured,
  QONRemoteConfigV2TransportFailureKindSuperseded,
  QONRemoteConfigV2TransportFailureKindBootstrapUnauthorized,
  QONRemoteConfigV2TransportFailureKindBootstrapNotFound,
  QONRemoteConfigV2TransportFailureKindBootstrapUnavailable,
  QONRemoteConfigV2TransportFailureKindBootstrapMalformed,
  QONRemoteConfigV2TransportFailureKindBootstrapTransport,
  QONRemoteConfigV2TransportFailureKindBootstrapPersistenceFailed,
  QONRemoteConfigV2TransportFailureKindSnapshotUnauthorized,
  QONRemoteConfigV2TransportFailureKindSnapshotNotFound,
  QONRemoteConfigV2TransportFailureKindSnapshotUnavailable,
  QONRemoteConfigV2TransportFailureKindSnapshotMalformed,
  QONRemoteConfigV2TransportFailureKindSnapshotTransport,
  /**
   The gateway stated a `project_id` that disagrees with the one this
   installation already learned for the same project and environment. Never
   re-learned: see QONRemoteConfigV2ProjectIdentityStore.
   */
  QONRemoteConfigV2TransportFailureKindProjectIdentityConflict,
  /** The learned `project_id` could not be made durable, so it was not used. */
  QONRemoteConfigV2TransportFailureKindProjectIdentityPersistenceFailed,
};

/** Never carries a token or a response body. */
typedef void (^QONRemoteConfigV2TransportFailureObserver)(
    QONRemoteConfigV2TransportFailureKind kind, NSNumber *_Nullable statusCode);

#pragma mark - Transport

/**
 Binds the fetch-policy engine to the dark gateway routes:
 POST {baseURL}/v3/remote-config-v2/session and
 POST {baseURL}/v3/remote-config-v2/snapshot.

 Snapshot bytes are handed to the coordinator exactly as received: the adapter
 never decodes or re-serializes the snapshot body.

 The one thing it does read out of a response body is the session bootstrap's
 `project_id`, which is the only place the SDK can learn it. It is established
 once per project and environment, kept durable, and thereafter only confirmed.

 The same session seam serves the activation ack route —
 POST {baseURL}/v3/remote-config-v2/ack — see `sendAck:forScope:completion:`.
 It is a strictly out-of-band signal: it shares the session, the bootstrap and
 the single re-bootstrap-on-401 rule, and nothing else. It can neither admit nor
 invalidate config data, and it never reports through the failure observer,
 which belongs to the fetch policy.
 */
@interface QONRemoteConfigV2GatewayTransport : NSObject <QONRemoteConfigV2FetchTransport,
                                                          QONRemoteConfigV2AckTransporting>
- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithBaseURL:(NSURL *)baseURL
                            projectToken:(NSString *)projectToken
                            httpExecutor:(id<QONRemoteConfigV2HTTPExecuting>)httpExecutor
                            sessionStore:(id<QONRemoteConfigV2GatewaySessionStoring>)sessionStore
                     projectIdentityStore:(id<QONRemoteConfigV2ProjectIdentityStoring>)projectIdentityStore
                   clientContextProvider:(id<QONRemoteConfigV2ClientContextProviding>)clientContextProvider
                                   clock:(id<QONRemoteConfigV2FetchClock>)clock
                         failureObserver:(nullable QONRemoteConfigV2TransportFailureObserver)failureObserver
    NS_DESIGNATED_INITIALIZER;
/**
 Must be driven with the same scope the coordinator binds. Passing nil unbinds
 the adapter; every in-flight request bound to the previous scope is abandoned
 and the retired scope's stored session token is dropped.
 */
- (void)updateScope:(nullable QONRemoteConfigV2Scope *)scope;
@end

NS_ASSUME_NONNULL_END
