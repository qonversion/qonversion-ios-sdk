#import <Foundation/Foundation.h>
#import "QONRemoteConfigV2Models.h"

@protocol QNLocalStorage;

NS_ASSUME_NONNULL_BEGIN

/**
 What happened when a bootstrapped `project_id` met what the device already knew.

 `Conflict` is terminal for the fetch that produced it. The numeric project id is
 not something the app states: it is learned from the gateway's session bootstrap
 response, which is the only party that knows it. Once learned it is stable, so a
 second bootstrap answering with a different one is either a misrouted response
 or a mis-provisioned gateway, and re-learning it would silently rebind the
 device's whole configuration to another project.
 */
typedef NS_ENUM(NSInteger, QONRemoteConfigV2ProjectIdentityOutcome) {
  /** Nothing was known; this bootstrap established it and it is now durable. */
  QONRemoteConfigV2ProjectIdentityOutcomeEstablished,
  /** Already known and identical. Nothing was written. */
  QONRemoteConfigV2ProjectIdentityOutcomeConfirmed,
  /** Already known and different. Never re-learned. */
  QONRemoteConfigV2ProjectIdentityOutcomeConflict,
  /** The stated id is outside the range a `project_id` can occupy. */
  QONRemoteConfigV2ProjectIdentityOutcomeUnusable,
  /** Storage refused the write, so the id would not survive a restart. */
  QONRemoteConfigV2ProjectIdentityOutcomePersistenceFailed,
};

/**
 The device's memory of the numeric `project_id` the gateway bootstrap stated.

 Deliberately keyed without the identity: a `project_id` is a property of the
 project, not of the user, so keying it per identity would let a logout and a
 fresh login launder a conflicting id past the check above. It also outlives the
 session record on purpose — a 401 drops the session token and re-bootstraps,
 and that is exactly the moment the previously learned id must still be there to
 compare against.

 It is keyed by everything that decides *which* project the gateway will answer
 for: the base URL and the project token as well as the project key and the
 environment. Two deployments of one project key — a staging gateway and a
 production one, or a token swap — legitimately carry different numeric ids, and
 a conflict is terminal, so a key that could not tell them apart would brick the
 surface on a routine environment switch.
 */
@protocol QONRemoteConfigV2ProjectIdentityStoring <NSObject>
/** The learned id, or 0 when nothing is known for this project and environment. */
- (int64_t)projectIDForScope:(QONRemoteConfigV2Scope *)scope;
- (QONRemoteConfigV2ProjectIdentityOutcome)establishProjectID:(int64_t)projectID
                                                     forScope:(QONRemoteConfigV2Scope *)scope;
@end

@interface QONRemoteConfigV2ProjectIdentityStore : NSObject <QONRemoteConfigV2ProjectIdentityStoring>
- (instancetype)init NS_UNAVAILABLE;
/** baseURL and projectToken must be the ones the transport fetches with. */
- (nullable instancetype)initWithLocalStorage:(id<QNLocalStorage>)localStorage
                                       baseURL:(NSURL *)baseURL
                                  projectToken:(NSString *)projectToken
    NS_DESIGNATED_INITIALIZER;
- (NSString *)storageKeyForScope:(QONRemoteConfigV2Scope *)scope;
@end

NS_ASSUME_NONNULL_END
