#import <Foundation/Foundation.h>
#import "QONRemoteConfigV2FetchCoordinator.h"

@protocol QNLocalStorage;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const QONRemoteConfigV2DeviceInstallDateStorageKey;

/**
 Device install date, in whole seconds since the epoch.

 The gateway treats this as a DEVICE fact: the server ages a user by
 min(device_installed_at, client.created_at), so a fresh anonymous row created
 after a logout must not make a long-time installation look new. The value is
 therefore never keyed by user, identity or project, and it is written exactly
 once per device.
 */
@protocol QONRemoteConfigV2DeviceInstallDateProviding <NSObject>
- (nullable NSNumber *)deviceInstalledAtSeconds;
@end

/**
 Device-scoped implementation backed by a single unscoped local-storage key.
 The stored value always wins over the supplied system fact, so the date is
 stable across launches, logouts and identity switches.
 */
@interface QONRemoteConfigV2DeviceInstallDateProvider : NSObject <QONRemoteConfigV2DeviceInstallDateProviding>
- (instancetype)init NS_UNAVAILABLE;

/**
 Reads the platform's install-date fact, which QNDevice states as whole seconds
 in a string, into the number this provider seeds itself with.

 Anything that is not a positive whole number of seconds — a missing fact, an
 empty string, a zero, a negative, a date the platform could not determine —
 becomes nil, which means "seed nothing" rather than "the device was installed
 at the epoch".
 */
+ (nullable NSNumber *)installDateSecondsFromSystemFact:(nullable NSString *)fact;
/**
 systemInstallDateSeconds is the platform-level install fact (QNDevice.installDate)
 and is only used to seed a device that has no stored value yet.
 */
- (nullable instancetype)initWithLocalStorage:(id<QNLocalStorage>)localStorage
                     systemInstallDateSeconds:(nullable NSNumber *)systemInstallDateSeconds
                                        clock:(id<QONRemoteConfigV2FetchClock>)clock
    NS_DESIGNATED_INITIALIZER;
@end

NS_ASSUME_NONNULL_END
