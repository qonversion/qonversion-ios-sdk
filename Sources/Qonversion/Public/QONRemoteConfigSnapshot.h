#import <Foundation/Foundation.h>
#import "QONRemoteConfigValue.h"

NS_ASSUME_NONNULL_BEGIN

typedef id _Nullable (^QONRemoteConfigValueDecoder)(NSData *rawData, NSError **error)
    NS_SWIFT_NAME(Qonversion.RemoteConfigValueDecoder);

NS_SWIFT_NAME(Qonversion.RemoteConfigSnapshot)
@interface QONRemoteConfigSnapshot : NSObject

- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, copy, readonly) NSString *releaseUID;
@property (nonatomic, assign, readonly) NSInteger releaseNumber;
@property (nonatomic, copy, readonly) NSString *manifestContentHash;
@property (nonatomic, copy, readonly) NSSet<NSString *> *allKeys;

- (nullable QONRemoteConfigValue *)rawValueForKey:(NSString *)key
    NS_SWIFT_NAME(rawValue(_:));
- (nullable QONRemoteConfigValue *)valueForKey:(NSString *)key
                                      decoder:(QONRemoteConfigValueDecoder)decoder
    NS_SWIFT_NAME(value(_:decoder:));
- (nullable id)metadataForKey:(NSString *)key NS_SWIFT_NAME(metadata(for:));

@end

NS_ASSUME_NONNULL_END
