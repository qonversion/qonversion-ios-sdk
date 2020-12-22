#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface QNAttributionManager : NSObject

- (void)addAttributionData:(NSDictionary *)data fromProvider:(NSInteger)provider;
- (void)addAppleSearchAttributionData;

@end

NS_ASSUME_NONNULL_END
