#import "QonversionLaunchResult.h"

@interface QonversionLaunchResult (Protected)

@property (nonatomic) NSUInteger timestamp;
@property (nonatomic, strong) NSDictionary<NSString *, QonversionPermission *> *permissions;
@property (nonatomic, strong) NSDictionary<NSString *, QonversionProduct *> *products;

@end