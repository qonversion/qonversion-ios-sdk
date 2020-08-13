#import <Foundation/Foundation.h>
#import "Qonversion.h"

NS_ASSUME_NONNULL_BEGIN

@interface QNAttributionManager : NSObject

- (void)addAttributionData:(NSDictionary *)data fromProvider:(QNAttributionProvider)provider;

@end

NS_ASSUME_NONNULL_END
