#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** Shared portable JSON profile for bundled artifacts and network candidates. */
FOUNDATION_EXPORT BOOL QONRemoteConfigIsPortableJSONData(NSData *data,
                                                          NSUInteger maximumBytes);
FOUNDATION_EXPORT id _Nullable QONRemoteConfigPortableJSONObject(NSData *data,
                                                                  NSUInteger maximumBytes);

NS_ASSUME_NONNULL_END
