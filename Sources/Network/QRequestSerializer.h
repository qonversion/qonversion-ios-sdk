#import <Foundation/Foundation.h>
#import <StoreKit/StoreKit.h>

#import "Qonversion.h"

@interface QRequestSerializer : NSObject

- (instancetype)initWithUserID:(NSString *)uid;

- (NSDictionary *)launchData;

- (NSDictionary *)purchaseData:(SKProduct *)product
                   transaction:(SKPaymentTransaction *)transaction;

- (NSDictionary *)attributionDataWithDict:(NSDictionary *)data
                             fromProvider:(QAttributionProvider)provider
                                   userID:(nullable NSString *)uid;

@end


