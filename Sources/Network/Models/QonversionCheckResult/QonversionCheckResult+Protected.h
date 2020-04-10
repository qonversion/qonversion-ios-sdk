#import "QonversionCheckResult.h"

@interface QonversionCheckResult (Protected)

@property (nonatomic) NSUInteger timestamp;
@property (nonatomic) ClientEnvironment environment;
@property (nonatomic, strong) NSArray<RenewalProductDetails *> *activeProducts;
@property (nonatomic, strong) NSArray<RenewalProductDetails *> *allProducts;

@end
