#import <Foundation/Foundation.h>
#import "QonversionMapper.h"
#import "QonversionCheckResult.h"

@interface QonversionCheckResult()

@property (nonatomic) NSUInteger timestamp;
@property (nonatomic) ClientEnvironment environment;
@property (nonatomic, strong) NSArray<RenewalProductDetails *> *activeProducts;
@property (nonatomic, strong) NSArray<RenewalProductDetails *> *allProducts;

@end


@implementation QonversionMapper

+ (QonversionCheckResult *)fillCheckResult:(NSDictionary *)dict {
  QonversionCheckResult *result = [QonversionCheckResult alloc] init];
  
  return result;
}

@end
