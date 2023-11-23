#import "QONLaunchResult.h"

@interface QONLaunchResult (Protected)

@property (nonatomic, copy) NSString *uid;
@property (nonatomic, assign) NSUInteger timestamp;
@property (nonatomic, copy) NSDictionary<NSString *, QONEntitlement *> *entitlements;
@property (nonatomic, copy) NSDictionary<NSString *, QONProduct *> *products;
@property (nonatomic, copy) NSDictionary<NSString *, QONProduct *> *userProducts;

@end
