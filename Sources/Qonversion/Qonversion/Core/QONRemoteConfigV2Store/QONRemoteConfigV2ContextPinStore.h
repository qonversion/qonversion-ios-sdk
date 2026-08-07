#import <Foundation/Foundation.h>
#import "QONRemoteConfigV2Models.h"

@protocol QNLocalStorage;

NS_ASSUME_NONNULL_BEGIN

/**
 Durable trust-on-first-use pin for the gateway's `context_fingerprint`.

 The fingerprint is never pre-provisioned: the server derives it from the full
 client context, which does not exist at bootstrap. The first strictly
 validated snapshot envelope of an identity scope therefore pins its
 fingerprint here, and every later admission in the same scope must match it or
 is refused. The pin is keyed by the full scope, identity included, exactly
 like the gateway session token — so an identity change resets it and nothing
 an earlier identity pinned can constrain or authorize the next one.

 It is deliberately as durable as the snapshot state it protects: a restart
 must not be able to re-pin a scope that is already pinned.
 */
@protocol QONRemoteConfigV2ContextPinStoring <NSObject>
- (nullable NSString *)contextFingerprintForScope:(QONRemoteConfigV2Scope *)scope;
- (BOOL)storeContextFingerprint:(NSString *)contextFingerprint
                       forScope:(QONRemoteConfigV2Scope *)scope;
- (void)removeContextFingerprintForScope:(QONRemoteConfigV2Scope *)scope;
@end

@interface QONRemoteConfigV2ContextPinStore : NSObject <QONRemoteConfigV2ContextPinStoring>
- (instancetype)init NS_UNAVAILABLE;
/** A write succeeds only after exact read-back verification. */
- (nullable instancetype)initWithLocalStorage:(id<QNLocalStorage>)localStorage
    NS_DESIGNATED_INITIALIZER;
+ (NSString *)storageKeyForScope:(QONRemoteConfigV2Scope *)scope;
@end

NS_ASSUME_NONNULL_END
