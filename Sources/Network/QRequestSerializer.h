#import <Foundation/Foundation.h>
#import <StoreKit/StoreKit.h>

@interface QRequestSerializer : NSObject

- (instancetype)initWithUserID:(NSString *)uid;

- (NSDictionary *)lauchData;

- (NSDictionary *)purchaseData:(SKProduct *)product transaction:(SKPaymentTransaction *)transaction;

@end


