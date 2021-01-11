#import "QNUtils.h"
#import "QNMapper.h"
#import "QNErrors.h"
#import "QNProduct.h"
#import "QNPermission.h"
#import "QNMapperObject.h"
#import "QNOfferings.h"
#import "QNOffering.h"

#import "QNLaunchResult+Protected.h"
#import "QNOfferings+Protected.h"
#import "QNOffering+Protected.h"

@implementation QNMapper

+ (QNLaunchResult * _Nonnull)fillLaunchResult:(NSDictionary *)dict {
  QNLaunchResult *result = [[QNLaunchResult alloc] init];
  
  NSArray *permissionsArray = dict[@"permissions"] ?: @[];
  NSArray *productsArray = dict[@"products"] ?: @[];
  NSArray *userProductsArray = dict[@"user_products"] ?: @[];
  NSArray *offeringsArray = dict[@"offerings"];
  
  NSNumber *timestamp = dict[@"timestamp"] ?: @0;
  
  [result setTimestamp:timestamp.unsignedIntegerValue];
  [result setUid:((NSString *)dict[@"uid"] ?: @"")];
  [result setPermissions:[self fillPermissions:permissionsArray]];
  [result setProducts:[self fillProducts:productsArray]];
  [result setUserProducts:[self fillProducts:userProductsArray]];
  
  if (offeringsArray.count > 0) {
    QNOfferings *offerings = [self fillOfferingsObject:offeringsArray];
    [result setOfferings:offerings];
  }
  
  return result;
}

+ (NSDictionary <NSString *, QNPermission *> *)fillPermissions:(NSArray *)data {
  NSMutableDictionary <NSString *, QNPermission *> *permissions = [NSMutableDictionary new];
  
  for (NSDictionary* itemDict in data) {
    QNPermission *item = [self fillPermission:itemDict];
    if (item && item.permissionID) {
      permissions[item.permissionID] = item;
    }
  }
  
  return [[NSDictionary alloc] initWithDictionary:permissions];
}

+ (NSDictionary <NSString *, QNProduct *> *)fillProducts:(NSArray *)data {
  NSMutableDictionary <NSString *, QNProduct *> *products = [NSMutableDictionary new];
  
  for (NSDictionary* itemDict in data) {
    QNProduct *item = [self fillProduct:itemDict];
    if (item && item.qonversionID) {
      products[item.qonversionID] = item;
    }
  }
  
  return [products copy];
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
  NSString *storeId = (NSString *)dict[@"store_id"];
  result.storeID = [storeId isKindOfClass:[NSString class]] ? storeId : nil;
  
  return result;
}

+ (QNOfferings * _Nonnull)fillOfferingsObject:(NSArray *)data {
  NSArray<QNOfferings *> * _Nonnull availableOfferings = [self fillOfferings:data];
  
  QNOffering *main;
  
  for (QNOffering *offering in availableOfferings) {
    if (offering.tag == QNOfferingTagMain) {
      main = offering;
      break;
    }
  }
  
  QNOfferings *offerings = [[QNOfferings alloc] initWithMainOffering:main availableOfferings:[availableOfferings copy]];
  
  return offerings;
}

+ (NSArray<QNOfferings *> * _Nonnull)fillOfferings:(NSArray *)data {
  NSMutableArray *offerings = [NSMutableArray new];
  
  for (NSDictionary *offeringData in data) {
    NSString *offeringIdentifier = offeringData[@"id"];
    QNOfferingTag tag = [self mapOfferingTag:offeringData];
    
    NSArray *productsData = offeringData[@"products"];
    NSDictionary<NSString *, QNProduct *> *products = [self fillProducts:productsData];
    
    QNOffering *offering = [[QNOffering alloc] initWithIdentifier:offeringIdentifier tag:tag products:[products allValues]];
    [offerings addObject:offering];
  }
  
  return [offerings copy];
}

+ (QNOfferingTag)mapOfferingTag:(NSDictionary *)offeringData {
  QNOfferingTag tag;
  NSInteger tagValue = [self mapInteger:offeringData[@"tag"] orReturn:0];;
  
  switch (tagValue) {
    case 1:
      tag = QNOfferingTagMain;
      break;
      
    default:
      tag = QNOfferingTagNone;
      break;
  }
  
  return tag;
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

