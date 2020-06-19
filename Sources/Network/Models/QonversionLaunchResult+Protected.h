#import "QonversionLaunchResult.h"

@interface QonversionLaunchResult (Protected)

@property (nonatomic) NSUInteger timestamp;
@property (nonatomic, strong) NSDictionary<NSString *, QonversionPermissionResult *> *permissions;
@property (nonatomic, strong) NSDictionary<NSString *, QonversionProductResult *> *products;

@end
