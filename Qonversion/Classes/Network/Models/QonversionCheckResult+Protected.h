#import "QonversionCheckResult.h"

NS_ASSUME_NONNULL_BEGIN

@interface QonversionCheckResult (Protected)

@property (nonatomic) NSUInteger timestamp;
@property (nonatomic) ClientEnvironment environment;
@property (nonatomic, strong) NSArray<RenewalProductDetails *> *activeProducts;
@property (nonatomic, strong) NSArray<RenewalProductDetails *> *allProducts;

@end

NS_ASSUME_NONNULL_END
