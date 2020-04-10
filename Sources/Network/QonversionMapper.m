#import <Foundation/Foundation.h>
#import "QonversionMapper.h"
#import "RenewalProductDetails.h"
#import "QonversionCheckResult+Protected.h"
#import "RenewalProductDetails+Protected.h"

static NSDictionary <NSString *, NSNumber *> *RenewalProductDetailsStatuses = nil;
static NSDictionary <NSString *, NSNumber *> *RenewalProductDetailsStates = nil;

@implementation QonversionMapper

+ (void)load {
    RenewalProductDetailsStatuses = @{
        @"cancelled": @0,
        @"active": @1,
        @"refunded": @2,
    };
    
    RenewalProductDetailsStates = @{
        @"trial": @0,
        @"subscription": @1,
    };
}

- (QonversionCheckResultComposeModel *)composeModelFrom:(NSData *)data {
    QonversionCheckResultComposeModel *result = [QonversionCheckResultComposeModel new];
    
    if (!data || ![data isKindOfClass:NSData.class]) {
        [result setError:[QonversionMapper error:@"Could not receive data" code:QErrorCodeFailedReceiveData]];
        return result;
    }
    
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:nil];
    
    if (!dict || ![dict respondsToSelector:@selector(valueForKey:)]) {
        [result setError:[QonversionMapper error:@"Could not parse response" code:QErrorCodeFailedParseResponse]];
        return result;
    }
    
    BOOL success = dict[@"success"];
    NSDictionary *resultData = dict[@"data"];
    
    if (success && resultData) {
        QonversionCheckResult *resultObject = [[QonversionMapper new] fillCheckResultWith:resultData];
        result.result = resultObject;
        return result;
    } else {
        NSString *message = dict[@"data.message"] ?: @"";
        [result setError:[QonversionMapper error:message code:QErrorCodeFailedParseResponse]];
        return result;
    }
}

- (QonversionCheckResult *)fillCheckResultWith:(NSDictionary *)dict {
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

- (NSArray<RenewalProductDetails *> *)fillRenewalProducts:(NSArray *)dict {
    NSMutableArray *products = [[NSMutableArray alloc] init];

    for (NSDictionary* itemDict in dict) {
        RenewalProductDetails *item = [self fillRenewalProduct:itemDict];
        if (item) {
            [products addObject:item];
        }
    }

    return [products copy];
}

- (RenewalProductDetails *)fillRenewalProduct:(NSDictionary *)dict {
    RenewalProductDetails *item = [[RenewalProductDetails alloc] init];
    
    NSString *productID = dict[@"product_id"] ?: @"";
    NSString *originalID = dict[@"original_transaction_id"] ?: @"";

    if (!productID || !originalID) {
        return nil;
    }
    
    NSNumber *created = dict[@"created_at"] ?: @0;
    NSNumber *purchased = dict[@"purchased_at"] ?: @0;
    NSNumber *expires = dict[@"expires_at"] ?: @0;
    NSNumber *expired = dict[@"expired"] ?: @0;
    NSNumber *billingRetry = dict[@"billing_retry"] ?: @0;
    
    [item setProductID:productID];
    [item setOriginalTransactionID:originalID];
    [item setCreatedAt:created.intValue];
    [item setPurchasedAt:purchased.intValue];
    [item setExpiresAt:expires.intValue];
    [item setExpired:expired.boolValue];
    [item setBillingRetry:billingRetry.boolValue];
    
    NSString *status = dict[@"status"] ?: @"";
    [item setStatus:(RenewalProductDetailsStatuses[status] ?: @-1).intValue];
    
    NSString *state = dict[@"state"] ?: @"";
    [item setState:(RenewalProductDetailsStates[state] ?: @-1).intValue];
    
    return item;
}

+ (NSError *)error:(NSString *)message code:(QErrorCode)errorCode  {
    NSDictionary *info = @{NSLocalizedDescriptionKey: NSLocalizedString(message, nil)};
    return [[NSError alloc] initWithDomain:QonversionErrorDomain code:errorCode userInfo:info];
}

@end

