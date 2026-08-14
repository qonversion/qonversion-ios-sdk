#import <Foundation/Foundation.h>

@class QONRemoteConfigSnapshot;

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(Qonversion.RemoteConfigUpdate)
@interface QONRemoteConfigUpdate : NSObject

- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, strong, readonly) QONRemoteConfigSnapshot *snapshot;
@property (nonatomic, copy, readonly) NSSet<NSString *> *changedKeys;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *metadataByKey;

@end


NS_ASSUME_NONNULL_END
