#import <Foundation/Foundation.h>
#import "RenewalProductDetails+Protected.h"

@implementation RenewalProductDetails : NSObject

- (void)setState:(RenewalProductState)state {
    _state = state;
}

- (void)setProductID:(NSString *)productID {
    _productID = [productID copy];
}

- (void)setOriginalTransactionID:(NSString *)originalTransactionID {
    _originalTransactionID = [originalTransactionID copy];
}

- (void)setStatus:(RenewalProductStatus)status {
    _status = status;
}

- (void)setPurchasedAt:(NSUInteger)purchasedAt {
    _purchasedAt = purchasedAt;
}

- (void)setExpired:(BOOL)expired {
    _expired = expired;
}

- (void)setCreatedAt:(NSUInteger)createdAt {
    _createdAt = createdAt;
}

- (void)setExpiresAt:(NSUInteger)expiresAt {
    _expiresAt = expiresAt;
}

@end
