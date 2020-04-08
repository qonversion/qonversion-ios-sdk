#import <Foundation/Foundation.h>
#import "QonversionMapper.h"
#import "RenewalProductDetails.h"
#import "QonversionCheckResult+Protected.h"
#import "RenewalProductDetails+Protected.h"

@implementation QonversionMapper

+ (QonversionCheckResult *)fillCheckResultWith:(NSDictionary *)dict {
    QonversionCheckResult *result = [[QonversionCheckResult alloc] init];
    
    NSNumber *timestamp = dict[@"timestamp"];
    NSNumber *environment = dict[@"environment"];
    
    NSArray *activeProductsDict = dict[@"active_renew_product"];
    NSArray *allProductsDict = dict[@"all_renewal_products"];
    
    [result setEnvironment:environment.intValue];
    [result setTimestamp:timestamp.intValue];

    id allProducts = [self fillRenewalProducts:allProductsDict];
    id activeProducts = [self fillRenewalProducts:activeProductsDict];

    [result setAllProducts:allProducts];
    [result setActiveProducts:activeProducts];

    return result;
}


+ (NSArray<RenewalProductDetails *> *)fillRenewalProducts:(NSArray *)dict {
    NSMutableArray *products = [[NSMutableArray alloc] init];

    for (NSDictionary* itemDict in dict) {
        RenewalProductDetails *item = [self fillRenewalProduct:itemDict];
        if (item) {
            [products addObject:item];
        }
    }

    return [products copy];
}

+ (RenewalProductDetails *)fillRenewalProduct:(NSDictionary *)dict {
    return nil;
}
@end

