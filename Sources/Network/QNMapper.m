#import "QNUtils.h"
#import "QNMapper.h"
#import "QNErrors.h"
#import "QNLaunchResult+Protected.h"
#import "QNMapperObject.h"

@implementation QNMapperObjec

@end

@implementation QNMapper

- (QNLaunchResult * _Nonnull)fillLaunchResult:(NSDictionary *)dict {
  QNLaunchResult *result = [[QNLaunchResult alloc] init];
  NSDictionary *permissionsDict = dict[@"permissions"] ?: @{};
  NSDictionary *productsDict = dict[@"products"] ?: @{};
  NSDictionary *userProductsDict = dict[@"user_products"] ?: @{};
  
  [result setUid:((NSString *)dict[@"uid"] ?: @"")];
  [result setPermissions:[self fillPermissions:permissionsDict]];
  [result setProducts:[self fillProducts:productsDict]];
  [result setUserProducts:[self fillProducts:userProductsDict]];
  
  return result;
}

- (NSDictionary <NSString *, QNPermission *> *)fillPermissions:(NSDictionary *)dict {
  NSMutableDictionary <NSString *, QNPermission *> *permissions = [NSMutableDictionary new];
  
  for (NSDictionary* itemDict in dict) {
    QNPermission *item = [self fillPermission:itemDict];
    if (item && item.permissionID) {
      permissions[item.permissionID] = item;
    }
  }
  
  return [[NSDictionary alloc] initWithDictionary:permissions];
}

- (NSDictionary <NSString *, QNProduct *> *)fillProducts:(NSDictionary *)dict {
  NSMutableDictionary <NSString *, QNProduct *> *products = [NSMutableDictionary new];
  
  for (NSDictionary* itemDict in dict) {
    QNProduct *item = [self fillProduct:itemDict];
    if (item && item.qonversionID) {
      products[item.qonversionID] = item;
    }
  }
  
  return [[NSDictionary alloc] initWithDictionary:products];
}

- (QNPermission * _Nonnull)fillPermission:(NSDictionary *)dict {
  QNPermission *result = [[QNPermission alloc] init];
  result.permissionID = dict[@"id"];
  result.isActive = ((NSNumber *)dict[@"active"] ?: @0).boolValue;
  result.renewState = ((NSNumber *)dict[@"renew_state"] ?: @0).intValue;
  result.productID = ((NSString *)dict[@"associated_product"] ?: @"");
  
  NSTimeInterval started = ((NSNumber *)dict[@"started_timestamp"] ?: @0).intValue;
  result.startedDate = [[NSDate alloc] initWithTimeIntervalSince1970:started];
  result.expirationDate = nil;
  
  if (dict[@"expiration_timestamp"]) {
    NSTimeInterval expiration = ((NSNumber *)dict[@"expiration_timestamp"] ?: @0).intValue;
    result.expirationDate = [[NSDate alloc] initWithTimeIntervalSince1970:expiration];
  }
  
  return result;
}

- (QNProduct * _Nonnull)fillProduct:(NSDictionary *)dict {
  QNProduct *result = [[QNProduct alloc] init];
  
  result.duration = ((NSNumber *)dict[@"duration"] ?: @0).integerValue;
  result.type = ((NSNumber *)dict[@"type"] ?: @0).integerValue;
  result.qonversionID = ((NSString *)dict[@"id"] ?: @"");
  result.storeID = ((NSString *)dict[@"store_id"] ?: @"");
  
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

@end

