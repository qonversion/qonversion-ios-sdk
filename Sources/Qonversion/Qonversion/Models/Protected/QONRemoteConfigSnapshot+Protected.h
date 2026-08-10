#import "QONRemoteConfigSnapshot.h"
#import "QONRemoteConfigUpdate.h"

@class QONRemoteConfigV2Release, QONRemoteConfigV2Entry;

NS_ASSUME_NONNULL_BEGIN

@interface QONRemoteConfigValue ()
- (instancetype)initWithValue:(id)value
                       source:(QONRemoteConfigValueSource)source
                      rawData:(NSData *)rawData
                 variationUID:(NSString *)variationUID
                  applyPolicy:(QONRemoteConfigApplyPolicy)applyPolicy
                     metadata:(nullable id)metadata;
@end

/**
 Told that a typed read rejected the value it was given, with the logical key and
 the release number of the candidate that failed (0 when the candidate was a
 bundled default, which belongs to no release).

 Diagnostics only. It runs after the read has already resolved, it can never
 change what the read returns, and a snapshot without an observer behaves
 exactly as it did before.
 */
typedef void (^QONRemoteConfigDecodeFailureObserver)(NSString *logicalKey,
                                                     NSInteger releaseNumber);

@interface QONRemoteConfigSnapshot ()
/**
 Non-atomic on purpose, which makes it a publish-before-escape contract: the
 owner must attach it while the snapshot is still private to the thread that
 built it, before handing the snapshot to anyone. Every reader afterwards sees
 it through that hand-off. Attaching to a snapshot the app already holds is a
 data race and is not allowed.
 */
@property (nonatomic, copy, nullable) QONRemoteConfigDecodeFailureObserver decodeFailureObserver;
- (instancetype)initWithPrimaryRelease:(nullable QONRemoteConfigV2Release *)primaryRelease
                        previousRelease:(nullable QONRemoteConfigV2Release *)previousRelease
                        fallbackRelease:(nullable QONRemoteConfigV2Release *)fallbackRelease;
/**
 The release number of the primary (served) release, or 0 when nothing is served.

 Deliberately not the public `releaseNumber`, which walks down to the previous
 and then the bundled release so a read always reports something: that walk is
 right for a read and wrong for an acknowledgement, which must name the release
 the gateway actually published.
 */
@property (nonatomic, assign, readonly) NSInteger servedReleaseNumber;
- (nullable QONRemoteConfigV2Entry *)effectiveEntryForKey:(NSString *)key;
@end

@interface QONRemoteConfigUpdate ()
- (instancetype)initWithSnapshot:(QONRemoteConfigSnapshot *)snapshot
                      changedKeys:(NSSet<NSString *> *)changedKeys
                    metadataByKey:(NSDictionary<NSString *, id> *)metadataByKey;
@end

NS_ASSUME_NONNULL_END
