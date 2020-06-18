#import <Foundation/Foundation.h>
#import <StoreKit/StoreKit.h>

@interface QRequestSerializer : NSObject

- (instancetype)initWithUserID:(NSString *)uid;

- (NSDictionary *)launchData;

- (NSDictionary *)purchaseData:(SKProduct *)product transaction:(SKPaymentTransaction *)transaction;

@end


