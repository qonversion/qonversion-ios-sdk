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
FOUNDATION_EXPORT NSUInteger const QONRemoteConfigV2MaximumEnvelopeBytes;
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
/** Exact JSON bytes supplied by the server, including insignificant whitespace. */
@property (nonatomic, copy, nullable, readonly) NSData *metadataData;
@property (nonatomic, assign, readonly, getter=isTombstone) BOOL tombstone;
- (nullable instancetype)initWithKey:(NSString *)key
                             rawData:(NSData *)rawData
                        variationUID:(NSString *)variationUID
                         applyPolicy:(QONRemoteConfigApplyPolicy)applyPolicy
                            metadata:(nullable id)metadata;
- (nullable instancetype)initWithTombstoneKey:(NSString *)key;
- (nullable instancetype)initWithKey:(NSString *)key
                             rawData:(NSData *)rawData
                        variationUID:(NSString *)variationUID
                         applyPolicy:(QONRemoteConfigApplyPolicy)applyPolicy
                        metadataData:(NSData *)metadataData;
- (BOOL)contentEquals:(nullable QONRemoteConfigV2Entry *)other;
@end

@interface QONRemoteConfigV2Release : NSObject <NSCopying>
@property (nonatomic, copy, readonly) NSString *releaseUID;
@property (nonatomic, assign, readonly) NSInteger releaseNumber;
@property (nonatomic, copy, readonly) NSString *manifestContentHash;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, QONRemoteConfigV2Entry *> *entries;
@property (nonatomic, copy, nullable, readonly) NSData *canonicalBody;
@property (nonatomic, copy, nullable, readonly) NSString *strongETag;
@property (nonatomic, assign, readonly) int64_t projectID;
@property (nonatomic, copy, nullable, readonly) NSString *contextFingerprint;
@property (nonatomic, assign, readonly) int64_t admissionOrdinal;
- (nullable instancetype)initWithReleaseUID:(NSString *)releaseUID
                              releaseNumber:(NSInteger)releaseNumber
                        manifestContentHash:(NSString *)manifestContentHash
                                    entries:(NSDictionary<NSString *, QONRemoteConfigV2Entry *> *)entries;
- (nullable instancetype)initWithReleaseUID:(NSString *)releaseUID
                              releaseNumber:(NSInteger)releaseNumber
                        manifestContentHash:(NSString *)manifestContentHash
                                    entries:(NSDictionary<NSString *, QONRemoteConfigV2Entry *> *)entries
                              canonicalBody:(nullable NSData *)canonicalBody
                                  strongETag:(nullable NSString *)strongETag
                                   projectID:(int64_t)projectID
                          contextFingerprint:(nullable NSString *)contextFingerprint
                           admissionOrdinal:(int64_t)admissionOrdinal;
- (nullable QONRemoteConfigV2Release *)releaseBySettingAdmissionOrdinal:(int64_t)admissionOrdinal;
- (BOOL)containsImmediateEntry;
- (BOOL)contentEquals:(nullable QONRemoteConfigV2Release *)other;
@end

@interface QONRemoteConfigV2State : NSObject <NSCopying>
@property (nonatomic, strong, nullable, readonly) QONRemoteConfigV2Release *candidate;
@property (nonatomic, strong, nullable, readonly) QONRemoteConfigV2Release *active;
@property (nonatomic, strong, nullable, readonly) QONRemoteConfigV2Release *previous;
@property (nonatomic, assign, readonly) BOOL didActivate;
@property (nonatomic, assign, readonly) int64_t latestAdmissionOrdinal;
- (nullable instancetype)initWithCandidate:(nullable QONRemoteConfigV2Release *)candidate
                            active:(nullable QONRemoteConfigV2Release *)active
                          previous:(nullable QONRemoteConfigV2Release *)previous
                       didActivate:(BOOL)didActivate;
- (nullable instancetype)initWithCandidate:(nullable QONRemoteConfigV2Release *)candidate
                                    active:(nullable QONRemoteConfigV2Release *)active
                                  previous:(nullable QONRemoteConfigV2Release *)previous
                               didActivate:(BOOL)didActivate
                    latestAdmissionOrdinal:(int64_t)latestAdmissionOrdinal;
@end

/** Expected privacy and rendering boundary for one exact resolved-snapshot response. */
@interface QONRemoteConfigV2EnvelopeExpectation : NSObject <NSCopying>
@property (nonatomic, assign, readonly) int64_t projectID;
@property (nonatomic, copy, readonly) NSString *environmentUID;
@property (nonatomic, copy, readonly) NSString *contextFingerprint;
- (nullable instancetype)initWithProjectID:(int64_t)projectID
                            environmentUID:(NSString *)environmentUID
                        contextFingerprint:(NSString *)contextFingerprint;
@end

@interface QONRemoteConfigV2Envelope : NSObject
@property (nonatomic, assign, readonly) int64_t projectID;
@property (nonatomic, copy, readonly) NSString *environmentUID;
@property (nonatomic, copy, readonly) NSString *contextFingerprint;
@property (nonatomic, strong, readonly) QONRemoteConfigV2Release *snapshotRelease;
@property (nonatomic, copy, readonly) NSString *eTag;
@property (nonatomic, copy, readonly) NSString *bodyDigest;
@property (nonatomic, copy, readonly) NSData *canonicalBody;
@end

/** Strict schema-1 parser. It never performs networking and returns nil on any ambiguity. */
@protocol QONRemoteConfigV2EnvelopeDecoding <NSObject>
- (nullable QONRemoteConfigV2Envelope *)parseBody:(NSData *)body
                                      strongETag:(NSString *)strongETag
                                     expectation:(QONRemoteConfigV2EnvelopeExpectation *)expectation;
@end

@interface QONRemoteConfigV2EnvelopeParser : NSObject <QONRemoteConfigV2EnvelopeDecoding>
@end

NS_ASSUME_NONNULL_END
