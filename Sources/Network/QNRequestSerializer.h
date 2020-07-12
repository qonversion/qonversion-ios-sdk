#import <Foundation/Foundation.h>

#import "Qonversion.h"

@interface QNRequestSerializer : NSObject

- (instancetype)initWithUserID:(NSString *)uid;

- (NSDictionary *)launchData;

- (NSDictionary *)purchaseData:(SKProduct *)product
                   transaction:(SKPaymentTransaction *)transaction;

- (NSDictionary *)attributionDataWithDict:(NSDictionary *)data fromProvider:(QonversionAttributionProvider)provider;

@end


