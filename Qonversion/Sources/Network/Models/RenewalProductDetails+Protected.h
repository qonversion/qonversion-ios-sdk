#import <Foundation/Foundation.h>
#import "RenewalProductDetails.h"

NS_ASSUME_NONNULL_BEGIN

@interface RenewalProductDetails (Protected)

@property (nonatomic) RenewalProductStatus status;
@property (nonatomic) RenewalProductState state;
  
@property (nonatomic, copy) NSString *productID;
@property (nonatomic, copy) NSString *originalTransactionID;

@property (nonatomic) NSUInteger createdAt;
@property (nonatomic) NSUInteger purchasedAt;
@property (nonatomic) NSUInteger expiresAt;
@property (nonatomic) BOOL expired;

@end

NS_ASSUME_NONNULL_END
