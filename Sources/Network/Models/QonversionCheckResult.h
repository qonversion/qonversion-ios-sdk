#import <Foundation/Foundation.h>
#import "RenewalProductDetails.h"

typedef void (^QonversionCheckFailer)(NSError *error);

typedef NS_ENUM(unsigned int, ClientEnvironment){
    ClientEnvironmentSandbox = 0,
    ClientEnvironmentProduction = 1
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
 All products
 */
@property (nonatomic, copy, readonly) NSArray<RenewalProductDetails *> *allProducts;

@end

