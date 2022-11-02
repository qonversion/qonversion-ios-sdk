#import "QNLaunchResult.h"

@interface QNLaunchResult (Protected)

@property (nonatomic, copy) NSString *uid;
@property (nonatomic, assign) NSUInteger timestamp;
@property (nonatomic, copy) NSDictionary<NSString *, QNExperimentInfo *> *experiments;
@property (nonatomic, copy) NSDictionary<NSString *, QNEntitlement *> *entitlements;
@property (nonatomic, copy) NSDictionary<NSString *, QNProduct *> *products;
@property (nonatomic, copy) NSDictionary<NSString *, QNProduct *> *userProducts;

@end
