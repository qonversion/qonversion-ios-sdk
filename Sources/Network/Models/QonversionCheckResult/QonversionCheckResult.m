#import <Foundation/Foundation.h>
#import "QonversionCheckResult+Protected.h"

@implementation QonversionCheckResult : NSObject

- (void)setEnvironment:(ClientEnvironment)environment {
    _environment = environment;
}

- (void)setTimestamp:(NSUInteger)timestamp {
    _timestamp = timestamp;
}

- (void)setActiveProducts:(NSArray<RenewalProductDetails *> *)activeProducts {
    _activeProducts = activeProducts;
}

- (void)setAllProducts:(NSArray<RenewalProductDetails *> *)allProducts {
    _allProducts = allProducts;
}

@end
