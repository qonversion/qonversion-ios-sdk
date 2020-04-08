#import <Foundation/Foundation.h>
#import "RenewalProductDetails.h"

@interface RenewalProductDetails (Protected)

@property (nonatomic) RenewalProductStatus status;
@property (nonatomic) RenewalProductState state;
  
@property (nonatomic, copy) NSString *productID;
@property (nonatomic, copy) NSString *originalTransactionID;

@property (nonatomic) NSUInteger createdAt;
@property (nonatomic) NSUInteger purchasedAt;
@property (nonatomic) NSUInteger expiresAt;
@property (nonatomic) BOOL expired;
@property (nonatomic) BOOL billingRetry;

@end
