#import "QNUtils.h"
#import "QNMapper.h"
#import "QONErrors.h"
#import "QONProduct.h"
#import "QONEntitlement.h"
#import "QNMapperObject.h"
#import "QONOfferings.h"
#import "QONOffering.h"
#import "QONIntroEligibility.h"
#import "QONExperimentInfo.h"
#import "QONExperimentGroup.h"

#import "QONLaunchResult+Protected.h"
#import "QONOfferings+Protected.h"
#import "QONOffering+Protected.h"
#import "QONIntroEligibility+Protected.h"
#import "QONExperimentInfo+Protected.h"
#import "QONExperimentGroup+Protected.h"
#import "QONUser+Protected.h"

@implementation QNMapper

+ (QONLaunchResult * _Nonnull)fillLaunchResult:(NSDictionary *)dict {
  QONLaunchResult *result = [[QONLaunchResult alloc] init];
  
  NSArray *permissionsArray = dict[@"permissions"] ?: @[];
  NSArray *productsArray = dict[@"products"] ?: @[];
  NSArray *userProductsArray = dict[@"user_products"] ?: @[];
  NSArray *offeringsArray = dict[@"offerings"];
  NSArray *experiments = dict[@"experiments"] ?: @[];
  
  NSNumber *timestamp = dict[@"timestamp"] ?: @0;
  
  [result setTimestamp:timestamp.unsignedIntegerValue];
  [result setUid:((NSString *)dict[@"uid"] ?: @"")];
  [result setEntitlements:[self fillPermissions:permissionsArray]];
  [result setProducts:[self fillProducts:productsArray]];
  [result setUserProducts:[self fillProducts:userProductsArray]];
  [result setExperiments:[self fillExperiments:experiments]];
  
  if (offeringsArray.count > 0) {
    QONOfferings *offerings = [self fillOfferingsObject:offeringsArray];
    [result setOfferings:offerings];
  }
  
  return result;
}

+ (NSDictionary * _Nullable)mapProductsEntitlementsRelation:(NSDictionary * _Nullable)dict {
  NSDictionary *relations = dict[@"products_permissions"];
  if ([relations isKindOfClass:[NSDictionary class]]) {
    return relations;
  } else {
    return nil;
  }
}

+ (QONUser *)fillUser:(NSDictionary * _Nullable)dict {
  NSString *userID = dict[@"uid"];
  NSString *originalAppVersion = dict[@"apple_extra"][@"original_application_version"];
  QONUser *user = [[QONUser alloc] initWithID:userID originalAppVersion:originalAppVersion];
  
  return user;
}

+ (NSDictionary <NSString *, QONEntitlement *> *)fillPermissions:(NSArray *)data {
  NSMutableDictionary <NSString *, QONEntitlement *> *permissions = [NSMutableDictionary new];
  
  for (NSDictionary* itemDict in data) {
    QONEntitlement *item = [self fillPermission:itemDict];
    if (item && item.entitlementID) {
      permissions[item.entitlementID] = item;
    }
  }
  
  return [[NSDictionary alloc] initWithDictionary:permissions];
}

+ (NSDictionary <NSString *, QONExperimentInfo *> *)fillExperiments:(NSArray *)data {
  NSMutableDictionary <NSString *, QONExperimentInfo *> *experiments = [NSMutableDictionary new];
  
  for (NSDictionary* itemDict in data) {
    QONExperimentInfo *item = [self fillExperiment:itemDict];
    if (item.identifier) {
      experiments[item.identifier] = item;
    }
  }
  
  return [experiments copy];
}

+ (QONExperimentInfo * _Nullable)fillExperiment:(NSDictionary *)dict {
  if (![dict isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  NSString *identifier = dict[@"uid"];
  if (!identifier) {
    return nil;
  }
  
  QONExperimentInfo *experiment = [[QONExperimentInfo alloc] initWithIdentifier:identifier group:nil];
  
  NSNumber *attachedNumber = dict[@"attached"];
  experiment.attached = attachedNumber.boolValue;
  
  return experiment;
}

+ (QONExperimentGroup * _Nonnull)fillExperimentGroup:(NSDictionary * _Nullable)dict {
  QNExperimentGroupType type = [self mapInteger:dict[@"type"] orReturn:0];
  QONExperimentGroup *group = [[QONExperimentGroup alloc] initWithType:type];
  
  return group;
}

+ (NSDictionary <NSString *, QONProduct *> *)fillProducts:(NSArray *)data {
  NSMutableDictionary <NSString *, QONProduct *> *products = [NSMutableDictionary new];
  NSArray <QONProduct *> *productsList = [self fillProductsToArray:data];
  
  for (QONProduct* product in productsList) {
    if (product.qonversionID) {
      products[product.qonversionID] = product;
    }
  }
  
  return [products copy];
}

+ (NSArray <QONProduct *> *)fillProductsToArray:(NSArray *)data {
  return [self fillProductsToArray:data offeringID:nil];
}

+ (NSArray <QONProduct *> *)fillProductsToArray:(NSArray *)data offeringID:(NSString * _Nullable)offeringID {
  NSMutableArray <QONProduct *> *products = [NSMutableArray new];
  
  for (NSDictionary* itemDict in data) {
    QONProduct *item = [self fillProduct:itemDict];
    item.offeringID = offeringID;
    if (item.qonversionID) {
      [products addObject:item];
    }
  }
  
  return [products copy];
}


+ (NSDictionary<NSString *, QONIntroEligibility *> * _Nonnull)mapProductsEligibility:(NSDictionary * _Nullable)dict {
  NSDictionary *introEligibilityStatuses = @{@"non_intro_or_trial_product": @(QONIntroEligibilityStatusNonIntroProduct),
                                             @"intro_or_trial_eligible": @(QONIntroEligibilityStatusEligible),
                                             @"intro_or_trial_ineligible": @(QONIntroEligibilityStatusIneligible)};
  
  NSArray *enrichedProducts = dict[@"products_enriched"];
  
  NSMutableDictionary<NSString *, QONIntroEligibility *> *eligibilityInfo = [NSMutableDictionary new];
  
  for (NSDictionary *item in enrichedProducts) {
    NSDictionary *productData = item[@"product"];
    if (!productData) {
      continue;
    }
    
    QONProduct *product = [self fillProduct:productData];
    NSString *eligibilityStatusString = item[@"intro_eligibility_status"];
    
    NSNumber *eligibilityValue = introEligibilityStatuses[eligibilityStatusString];
    QONIntroEligibilityStatus eligibilityStatus = eligibilityValue ? eligibilityValue.integerValue : QONIntroEligibilityStatusUnknown;
    QONIntroEligibility *eligibility = [[QONIntroEligibility alloc] initWithStatus:eligibilityStatus];
    
    eligibilityInfo[product.qonversionID] = eligibility;
  }
  
  return [eligibilityInfo copy];
}

+ (QONEntitlement * _Nonnull)fillPermission:(NSDictionary *)dict {
  NSDictionary *sources = @{
       @"appstore": @(QONEntitlementSourceAppStore),
       @"playstore": @(QONEntitlementSourcePlayStore),
       @"stripe": @(QONEntitlementSourceStripe),
       @"manual": @(QONEntitlementSourceManual),
       @"unknown": @(QONEntitlementSourceUnknown)
     };
  
  QONEntitlement *result = [[QONEntitlement alloc] init];
  result.entitlementID = dict[@"id"];
  result.isActive = ((NSNumber *)dict[@"active"] ?: @0).boolValue;
  result.renewState = [self mapInteger:dict[@"renew_state"] orReturn:0];
  
  NSString *sourceRaw = dict[@"source"];
  NSNumber *sourceNumber = sources[sourceRaw];
  QONEntitlementSource source = sourceNumber ? sourceNumber.integerValue : QONEntitlementSourceUnknown;
  result.source = source;
  
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

+ (QONProduct * _Nonnull)fillProduct:(NSDictionary *)dict {
  QONProduct *result = [[QONProduct alloc] init];
  
  QONProductDuration duration = [self mapInteger:dict[@"duration"] orReturn:-1];
  result.duration = duration;
  
  result.type = [self mapInteger:dict[@"type"] orReturn:0];
  
  result.qonversionID = ((NSString *)dict[@"id"] ?: @"");
  NSString *storeId = (NSString *)dict[@"store_id"];
  result.storeID = [storeId isKindOfClass:[NSString class]] ? storeId : nil;
  
  return result;
}

+ (QONOfferings * _Nonnull)fillOfferingsObject:(NSArray *)data {
  NSArray<QONOfferings *> * _Nonnull availableOfferings = [self fillOfferings:data];
  
  QONOffering *main;
  
  for (QONOffering *offering in availableOfferings) {
    if (offering.tag == QONOfferingTagMain) {
      main = offering;
      break;
    }
  }
  
  QONOfferings *offerings = [[QONOfferings alloc] initWithMainOffering:main availableOfferings:[availableOfferings copy]];
  
  return offerings;
}

+ (NSArray<QONOfferings *> * _Nonnull)fillOfferings:(NSArray *)data {
  NSMutableArray *offerings = [NSMutableArray new];
  
  for (NSDictionary *offeringData in data) {
    NSString *offeringIdentifier = offeringData[@"id"];
    QONOfferingTag tag = [self mapOfferingTag:offeringData];
    
    NSArray *productsData = offeringData[@"products"];
    
    NSArray<QONProduct *> *products = [self fillProductsToArray:productsData offeringID:offeringIdentifier];
    NSDictionary *experimentInfoData = offeringData[@"experiment"];

    QONExperimentInfo *experimentInfo = [self fillExperiment:experimentInfoData];
    QONOffering *offering = [[QONOffering alloc] initWithIdentifier:offeringIdentifier tag:tag products:products experimentInfo:experimentInfo];
    [offerings addObject:offering];
  }
  
  return [offerings copy];
}

+ (QONOfferingTag)mapOfferingTag:(NSDictionary *)offeringData {
  QONOfferingTag tag;
  NSNumber *tagNumber = offeringData[@"tag"];
  if (tagNumber) {
    switch (tagNumber.integerValue) {
      case 0:
        tag = QONOfferingTagNone;
        break;

      case 1:
        tag = QONOfferingTagMain;
        break;
        
      default:
        tag = QONOfferingTagUnknown;
        break;
    }
  } else {
    tag = QONOfferingTagNone;
  }
  
  return tag;
}

+ (QNMapperObject *)mapperObjectFrom:(NSDictionary *)dict {
  QNMapperObject *object = [QNMapperObject new];
  
  if (!dict || ![dict isKindOfClass:NSDictionary.class]) {
    [object setError:[QONErrors errorWithCode:QONAPIErrorFailedReceiveData]];
    return object;
  }
  
  NSNumber *success = dict[@"success"];
  NSDictionary *resultData = dict[@"data"];
  
  if (success.boolValue && resultData) {
    [object setData:resultData];
    return object;
  } else {
    [object setError:[QONErrors errorWithCode:QONAPIErrorIncorrectRequest]];
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

