#import "QNLaunchResult.h"

@interface QNLaunchResult (Protected)

@property (nonatomic, strong) NSString *uid;
@property (nonatomic) NSUInteger timestamp;
@property (nonatomic, strong) NSDictionary<NSString *, QNPermission *> *permissions;
@property (nonatomic, strong) NSDictionary<NSString *, QNProduct *> *products;
@property (nonatomic, strong) NSDictionary<NSString *, QNProduct *> *userProducts;

@end
