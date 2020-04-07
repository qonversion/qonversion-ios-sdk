#import <Foundation/Foundation.h>
#import "RenewalProductDetails.h"

typedef NS_ENUM(NSInteger, ClientEnvironment){
    ClientEnvironmentSandbox,
    ClientEnvironmentProduction
};

@interface QonversionCheckResult : NSObject

/**
 Original Server response time
 */
@property (nonatomic, readonly) NSUInteger timestamp;

/**
  The environment for which the receipt was generated.
 */
@property (nonatomic, readonly) ClientEnvironment environment;

/**
 Only active user products,
 Doesn't include non expired products that were refunded
 */
@property (nonatomic, copy, readonly) NSArray<RenewalProductDetails *> *activeProducts;

/**
 All product
 */
@property (nonatomic, copy, readonly) NSArray<RenewalProductDetails *> *allProducts;

@end
