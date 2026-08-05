#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, QONRemoteConfigValueSource) {
  QONRemoteConfigValueSourceServer = 0,
  QONRemoteConfigValueSourceCache = 1,
  QONRemoteConfigValueSourceFallback = 2,
} NS_SWIFT_NAME(Qonversion.RemoteConfigValueSource);

typedef NS_ENUM(NSInteger, QONRemoteConfigApplyPolicy) {
  QONRemoteConfigApplyPolicyOnNextActivate = 0,
  QONRemoteConfigApplyPolicyImmediate = 1,
} NS_SWIFT_NAME(Qonversion.RemoteConfigApplyPolicy);

NS_SWIFT_NAME(Qonversion.RemoteConfigValue)
@interface QONRemoteConfigValue : NSObject

- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, strong, readonly) id value;
@property (nonatomic, assign, readonly) QONRemoteConfigValueSource source;
@property (nonatomic, copy, readonly) NSData *rawData;
@property (nonatomic, copy, readonly) NSString *variationUID;
@property (nonatomic, assign, readonly) QONRemoteConfigApplyPolicy applyPolicy;
@property (nonatomic, copy, nullable, readonly) id metadata;

@end

NS_ASSUME_NONNULL_END
