#import <Foundation/Foundation.h>
#import "QONRemoteConfigSnapshot.h"
#import "QONRemoteConfigUpdate.h"

@class QONRemoteConfigV2Release, QONRemoteConfigV2Scope, QONRemoteConfigV2Store;

NS_ASSUME_NONNULL_BEGIN

typedef void (^QONRemoteConfigV2UpdateObserver)(QONRemoteConfigUpdate *update);

@interface QONRemoteConfigV2Manager : NSObject

@property (nonatomic, strong, readonly) QONRemoteConfigSnapshot *currentSnapshot;
@property (nonatomic, strong, nullable, readonly) QONRemoteConfigSnapshot *lastFetchedSnapshot;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithStore:(QONRemoteConfigV2Store *)store
               fallbackRelease:(nullable QONRemoteConfigV2Release *)fallbackRelease
             fallbackProjectKey:(nullable NSString *)fallbackProjectKey
            fallbackEnvironment:(nullable NSString *)fallbackEnvironment NS_DESIGNATED_INITIALIZER;
- (void)setScope:(nullable QONRemoteConfigV2Scope *)scope;
- (void)acceptFetchedRelease:(QONRemoteConfigV2Release *)release
                     forScope:(QONRemoteConfigV2Scope *)scope;
- (BOOL)activate;
- (id)addUpdateObserver:(QONRemoteConfigV2UpdateObserver)observer;
- (void)removeUpdateObserver:(id)token;

@end

NS_ASSUME_NONNULL_END
