#import <Foundation/Foundation.h>
#import "QONRemoteConfigValue.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSUInteger const QONRemoteConfigV2MaximumEntryCount;
FOUNDATION_EXPORT NSUInteger const QONRemoteConfigV2MaximumRawValueBytes;
FOUNDATION_EXPORT NSUInteger const QONRemoteConfigV2MaximumMetadataBytes;
FOUNDATION_EXPORT NSUInteger const QONRemoteConfigV2MaximumTotalValueBytes;
FOUNDATION_EXPORT NSUInteger const QONRemoteConfigV2MaximumKeyBytes;
FOUNDATION_EXPORT NSUInteger const QONRemoteConfigV2MaximumUIDCodePoints;
FOUNDATION_EXPORT NSUInteger const QONRemoteConfigV2MaximumScopeComponentBytes;
FOUNDATION_EXPORT int64_t const QONRemoteConfigV2MaximumSafeInteger;

@interface QONRemoteConfigV2Scope : NSObject <NSCopying>
@property (nonatomic, copy, readonly) NSString *projectKey;
@property (nonatomic, copy, readonly) NSString *environment;
@property (nonatomic, copy, readonly) NSString *canonicalUserID;
- (nullable instancetype)initWithProjectKey:(NSString *)projectKey
                                environment:(NSString *)environment
                            canonicalUserID:(NSString *)canonicalUserID;
@end

@interface QONRemoteConfigV2Entry : NSObject <NSCopying>
@property (nonatomic, copy, readonly) NSString *key;
@property (nonatomic, copy, nullable, readonly) NSData *rawData;
@property (nonatomic, copy, nullable, readonly) NSString *variationUID;
@property (nonatomic, assign, readonly) QONRemoteConfigApplyPolicy applyPolicy;
@property (nonatomic, copy, nullable, readonly) id metadata;
@property (nonatomic, assign, readonly, getter=isTombstone) BOOL tombstone;
- (nullable instancetype)initWithKey:(NSString *)key
                             rawData:(NSData *)rawData
                        variationUID:(NSString *)variationUID
                         applyPolicy:(QONRemoteConfigApplyPolicy)applyPolicy
                            metadata:(nullable id)metadata;
- (nullable instancetype)initWithTombstoneKey:(NSString *)key;
- (BOOL)contentEquals:(nullable QONRemoteConfigV2Entry *)other;
@end

@interface QONRemoteConfigV2Release : NSObject <NSCopying>
@property (nonatomic, copy, readonly) NSString *releaseUID;
@property (nonatomic, assign, readonly) NSInteger releaseNumber;
@property (nonatomic, copy, readonly) NSString *manifestContentHash;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, QONRemoteConfigV2Entry *> *entries;
- (nullable instancetype)initWithReleaseUID:(NSString *)releaseUID
                              releaseNumber:(NSInteger)releaseNumber
                        manifestContentHash:(NSString *)manifestContentHash
                                    entries:(NSDictionary<NSString *, QONRemoteConfigV2Entry *> *)entries;
- (BOOL)containsImmediateEntry;
- (BOOL)contentEquals:(nullable QONRemoteConfigV2Release *)other;
@end

@interface QONRemoteConfigV2State : NSObject <NSCopying>
@property (nonatomic, strong, nullable, readonly) QONRemoteConfigV2Release *candidate;
@property (nonatomic, strong, nullable, readonly) QONRemoteConfigV2Release *active;
@property (nonatomic, strong, nullable, readonly) QONRemoteConfigV2Release *previous;
@property (nonatomic, assign, readonly) BOOL didActivate;
- (nullable instancetype)initWithCandidate:(nullable QONRemoteConfigV2Release *)candidate
                            active:(nullable QONRemoteConfigV2Release *)active
                          previous:(nullable QONRemoteConfigV2Release *)previous
                       didActivate:(BOOL)didActivate;
@end

NS_ASSUME_NONNULL_END
