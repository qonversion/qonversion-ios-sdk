#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, RenewalProductState){
    RenewalProductStateTrial,
    RenewalProductStateSubscription
};

typedef NS_ENUM(NSInteger, RenewalProductStatus){
    RenewalProductStatusActive,
    RenewalProductStatusCancelled,
    RenewalProductStatusRefunded
};

@interface RenewalProductDetails : NSObject

@property (nonatomic, readonly) RenewalProductStatus status;
@property (nonatomic, readonly) RenewalProductState state;
  
@property (nonatomic, copy, readonly) NSString *productID;
@property (nonatomic, copy, readonly) NSString *originalTransactionID;
@property (nonatomic, copy, readonly) NSString *originalTransactionID;

@property (nonatomic, readonly) NSUInteger createdAt;
@property (nonatomic, readonly) NSUInteger purchasedAt;
@property (nonatomic, readonly) NSUInteger expiresAt;
@property (nonatomic, readonly) BOOL expired;

@end
