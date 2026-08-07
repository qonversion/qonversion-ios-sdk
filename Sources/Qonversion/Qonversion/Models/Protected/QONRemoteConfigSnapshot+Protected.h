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

@interface QONRemoteConfigSnapshot ()
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
