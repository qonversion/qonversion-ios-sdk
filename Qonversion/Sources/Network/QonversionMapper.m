#import <Foundation/Foundation.h>
#import "QonversionMapper.h"
#import "RenewalProductDetails.h"
#import "QonversionCheckResult+Protected.h"

@implementation QonversionMapper

+ (QonversionCheckResult *)fillCheckResultWith:(NSDictionary *)dict {
    QonversionCheckResult *result = [[QonversionCheckResult alloc] init];
    
    NSNumber *timestamp = dict[@"timestamp"];
    NSNumber *environment = dict[@"environment"];
    
    NSDictionary *activeProductsDict = dict[@"active_renew_product"];
    NSDictionary *allProductsDict = dict[@"all_renewal_products"];
    
    NSMutableArray <RenewalProductDetails *> *activeProducts = [NSMutableArray array];
    NSMutableArray <RenewalProductDetails *> *allProducts = [NSMutableArray array];
    
    [result setEnvironment:environment.intValue];
    [result setTimestamp:timestamp.intValue];
    
    [result setAllProducts:[allProducts copy]];
    [result setActiveProducts:[activeProducts copy]];
    
    return result;
}

@end

