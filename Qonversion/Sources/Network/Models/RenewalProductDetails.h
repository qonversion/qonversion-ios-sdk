#import <Foundation/Foundation.h>

typedef NS_ENUM(unsigned int, RenewalProductState){
    RenewalProductStateTrial = 0,
    RenewalProductStateSubscription = 1
};

typedef NS_ENUM(unsigned int, RenewalProductStatus){
    RenewalProductStatusCancelled = 0,
    RenewalProductStatusActive = 1,
    RenewalProductStatusRefunded = 2
};

@interface RenewalProductDetails : NSObject

@property (nonatomic, readonly) RenewalProductStatus status;
@property (nonatomic, readonly) RenewalProductState state;
  
@property (nonatomic, copy, readonly) NSString *productID;
@property (nonatomic, copy, readonly) NSString *originalTransactionID;

@property (nonatomic, readonly) NSUInteger createdAt;
@property (nonatomic, readonly) NSUInteger purchasedAt;
@property (nonatomic, readonly) NSUInteger expiresAt;
@property (nonatomic, readonly) BOOL expired;

@end
