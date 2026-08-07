#import <Foundation/Foundation.h>
#import "QONRemoteConfigV2Models.h"

@protocol QNLocalStorage;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSUInteger const QONRemoteConfigV2GatewaySessionMaximumTokenBytes;

/**
 A header field value must be visible ASCII (optionally spaced), otherwise
 CFNetwork drops the header silently and the request goes out unauthenticated.
 */
FOUNDATION_EXPORT BOOL QONRemoteConfigV2GatewayValidHeaderValue(NSString *_Nullable value,
                                                                NSUInteger maximumBytes);

/** Bootstrap result for one identity scope. Tokens are never logged. */
@interface QONRemoteConfigV2GatewaySession : NSObject <NSCopying>
@property (nonatomic, copy, readonly) NSString *sessionToken;
@property (nonatomic, assign, readonly) int64_t projectID;
@property (nonatomic, copy, readonly) NSString *environment;
/** Whole seconds since the epoch, or 0 when the server did not state an expiry. */
@property (nonatomic, assign, readonly) int64_t expiresAtSeconds;
- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithSessionToken:(NSString *)sessionToken
                                    projectID:(int64_t)projectID
                                  environment:(NSString *)environment
                             expiresAtSeconds:(int64_t)expiresAtSeconds
    NS_DESIGNATED_INITIALIZER;
@end

/**
 Session tokens are bound to the full remote config scope, identity included, so
 an identity change can never reuse the previous identity's token.
 */
@protocol QONRemoteConfigV2GatewaySessionStoring <NSObject>
- (nullable QONRemoteConfigV2GatewaySession *)sessionForScope:(QONRemoteConfigV2Scope *)scope;
- (BOOL)storeSession:(QONRemoteConfigV2GatewaySession *)session
            forScope:(QONRemoteConfigV2Scope *)scope;
- (void)removeSessionForScope:(QONRemoteConfigV2Scope *)scope;
@end

@interface QONRemoteConfigV2GatewaySessionStore : NSObject <QONRemoteConfigV2GatewaySessionStoring>
- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithLocalStorage:(id<QNLocalStorage>)localStorage
    NS_DESIGNATED_INITIALIZER;
+ (NSString *)storageKeyForScope:(QONRemoteConfigV2Scope *)scope;
@end

NS_ASSUME_NONNULL_END
