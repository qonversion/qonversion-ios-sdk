#import <Foundation/Foundation.h>
#import "QONRemoteConfigV2FetchCoordinator.h"

@protocol QNLocalStorage;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSUInteger const QONRemoteConfigV2FetchPolicyMaximumArchiveBytes;

/** Small, identity-independent durable guard state keyed by project and environment. */
@interface QONRemoteConfigV2FetchPolicyStore : NSObject <QONRemoteConfigV2FetchPolicyStoring>
- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithLocalStorage:(id<QNLocalStorage>)localStorage NS_DESIGNATED_INITIALIZER;
@end

NS_ASSUME_NONNULL_END
