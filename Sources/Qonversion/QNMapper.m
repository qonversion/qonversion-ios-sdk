#import "QNUtils.h"
#import "QNMapper.h"
#import "QNErrors.h"
#import "QNLaunchResult+Protected.h"
#import "QNProduct.h"
#import "QNPermission.h"
#import "QNMapperObject.h"

@implementation QNMapper

+ (QNLaunchResult * _Nonnull)fillLaunchResult:(NSDictionary *)dict {
  QNLaunchResult *result = [[QNLaunchResult alloc] init];
  
  NSDictionary *permissionsDict = dict[@"permissions"] ?: @{};
  NSDictionary *productsDict = dict[@"products"] ?: @{};
  NSDictionary *userProductsDict = dict[@"user_products"] ?: @{};
  NSNumber *timestamp = dict[@"timestamp"] ?: @0;
  
  [result setTimestamp:timestamp.unsignedIntegerValue];
  [result setUid:((NSString *)dict[@"uid"] ?: @"")];
  [result setPermissions:[self fillPermissions:permissionsDict]];
  [result setProducts:[self fillProducts:productsDict]];
  [result setUserProducts:[self fillProducts:userProductsDict]];
  
  return result;
}

+ (NSDictionary <NSString *, QNPermission *> *)fillPermissions:(NSDictionary *)dict {
  NSMutableDictionary <NSString *, QNPermission *> *permissions = [NSMutableDictionary new];
  
  for (NSDictionary* itemDict in dict) {
    QNPermission *item = [self fillPermission:itemDict];
    if (item && item.permissionID) {
      permissions[item.permissionID] = item;
    }
  }
  
  return [[NSDictionary alloc] initWithDictionary:permissions];
}

+ (NSDictionary <NSString *, QNProduct *> *)fillProducts:(NSDictionary *)dict {
  NSMutableDictionary <NSString *, QNProduct *> *products = [NSMutableDictionary new];
  
  for (NSDictionary* itemDict in dict) {
    QNProduct *item = [self fillProduct:itemDict];
    if (item && item.qonversionID) {
      products[item.qonversionID] = item;
    }
  }
  
  return [[NSDictionary alloc] initWithDictionary:products];
}

+ (QNPermission * _Nonnull)fillPermission:(NSDictionary *)dict {
  QNPermission *result = [[QNPermission alloc] init];
  result.permissionID = dict[@"id"];
  result.isActive = ((NSNumber *)dict[@"active"] ?: @0).boolValue;
  result.renewState = [self mapInteger:dict[@"renew_state"] orReturn:0];
  
  result.productID = ((NSString *)dict[@"associated_product"] ?: @"");
  
  NSTimeInterval started = [self mapInteger:dict[@"started_timestamp"] orReturn:0];
  result.startedDate = [[NSDate alloc] initWithTimeIntervalSince1970:started];
  result.expirationDate = nil;
  
  if ([dict[@"expiration_timestamp"] isEqual:[NSNull null]] == NO) {
    NSTimeInterval expiration = ((NSNumber *)dict[@"expiration_timestamp"] ?: @0).intValue;
    result.expirationDate = [[NSDate alloc] initWithTimeIntervalSince1970:expiration];
  }
  
  return result;
}

+ (QNProduct * _Nonnull)fillProduct:(NSDictionary *)dict {
  QNProduct *result = [[QNProduct alloc] init];
  
  QNProductDuration duration = [self mapInteger:dict[@"duration"] orReturn:-1];
  result.duration = duration;
  
  result.type = [self mapInteger:dict[@"type"] orReturn:0];
  
  result.qonversionID = ((NSString *)dict[@"id"] ?: @"");
  NSString *storeId = ((NSString *)dict[@"store_id"] ?: @"");
  result.storeID = [storeId isKindOfClass:[NSString class]] ? storeId : nil;
  
  return result;
}

+ (QNMapperObject *)mapperObjectFrom:(NSDictionary *)dict {
  QNMapperObject *object = [QNMapperObject new];
  
  if (!dict || ![dict isKindOfClass:NSDictionary.class]) {
    [object setError:[QNErrors errorWithCode:QNAPIErrorFailedReceiveData]];
    return object;
  }
  
  NSNumber *success = dict[@"success"];
  NSDictionary *resultData = dict[@"data"];
  
  if (success.boolValue && resultData) {
    [object setData:resultData];
    return object;
  } else {
    [object setError:[QNErrors errorWithCode:QNAPIErrorIncorrectRequest]];
    return object;
  }
}

+ (NSInteger)mapInteger:(NSObject *)object orReturn:(NSInteger)defaultValue {
  if (object == nil) {
    return defaultValue;
  }
  
  NSNumber *numberObject = (NSNumber *)object;
  
  if ([numberObject isEqual:[NSNull null]]) {
    return defaultValue;
  } else {
    return numberObject.integerValue;
  }
}

@end

