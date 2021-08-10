//
//  QNUserInfoMapper.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 19.05.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QNUserInfoMapper.h"
#import "QNUser+Protected.h"
#import "QNUserProduct+Protected.h"
#import "QNEntitlement+Protected.h"
#import "QNPurchase+Protected.h"
#import "QNSubscription+Protected.h"
#import "QNUtils.h"

@interface QNUserInfoMapper ()

@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *platformTypes;
@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *renewStates;
@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *userProductTypes;
@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *currentPeriodTypes;

@end

@implementation QNUserInfoMapper

- (instancetype)init {
  self = [super init];
  
  if (self) {
    _platformTypes = @{
      @"app_store": @(QNPurchasePlatformIOS),
      @"play_store": @(QNPurchasePlatformAndroid),
      @"stripe": @(QNPurchasePlatformStripe),
      @"promo": @(QNPurchasePlatformPromo)
    };
    
    _renewStates = @{
      @"will_renew": @(QNSubscriptionRenewStateWillRenew),
      @"canceled": @(QNSubscriptionRenewStateCanceled),
      @"billing_issue": @(QNSubscriptionRenewStateBillingIssue)
    };
    
    _userProductTypes = @{
      @"non_recurring_product": @(QNUserProductTypeNonRecurring),
      @"subscription": @(QNUserProductTypeSubscription)
    };
    
    _currentPeriodTypes = @{
      @"normal": @(QNSubscriptionPeriodTypeNormal),
      @"trial": @(QNSubscriptionPeriodTypeTrial),
      @"intro": @(QNSubscriptionPeriodTypeIntro)
    };
  }
  
  return self;
}

- (QNUser *)mapUserInfo:(NSDictionary *)data {
  NSDictionary *userData = [self getDataFromObject:data];

  NSString *userID = userData[@"id"];
  NSString *originalAppVersion = userData[@"originalAppVersion"];
  
  QNUser *user = [[QNUser alloc] initWithID:userID
                         originalAppVersion:originalAppVersion];
  
  return user;
}

- (NSArray<QNEntitlement *> *)mapEntitlements:(NSArray *)entitlementsData {
  if (entitlementsData.count == 0) {
    return @[];
  }
  
  NSMutableArray<QNEntitlement *> *entitlements = [NSMutableArray new];

  for (NSDictionary *data in entitlementsData) {
    NSString *object = data[@"object"];
    NSNumber *active = data[@"active"];
    NSString *entitlementID = data[@"entitlement"];
    NSString *userID = data[@"user"];
    
    NSNumber *startedTimestamp = data[@"started"];
    NSDate *startedDate = [QNUtils dateFromTimestamp:startedTimestamp];
  
    NSNumber *expirationTimestamp = data[@"expires"];
    NSDate *expirationDate = [QNUtils dateFromTimestamp:expirationTimestamp];
    
    NSArray *purchasesData = data[@"purchases"];
    NSArray *purchases = [self mapPurchases:purchasesData];
    
    QNEntitlement *entitlement = [[QNEntitlement alloc] initWithID:entitlementID
                                                            userID:userID
                                                            active:[active boolValue]
                                                       startedDate:startedDate
                                                    expirationDate:expirationDate
                                                         purchases:purchases
                                                            object:object];
    
    [entitlements addObject:entitlement];
  }
  
  return [entitlements copy];
}

- (NSArray<QNPurchase *> *)mapPurchases:(NSArray *)purchasesData {
  if (purchasesData.count == 0) {
    return @[];
  }
  
  NSMutableArray<QNPurchase *> *purchases = [NSMutableArray new];
  
  for (NSDictionary *data in purchasesData) {
    NSString *object = data[@"object"];
    NSString *userID = data[@"user"];
    NSString *originalID = data[@"original_id"];
    NSString *token = data[@"token"];
    NSString *platformProductID = data[@"platform_product_id"];
    
    NSString *platformRawValue = data[@"platform"];
    NSNumber *platformNumber = self.platformTypes[platformRawValue];
    QNPurchasePlatform platform = platformNumber ? platformNumber.integerValue : QNPurchasePlatformUnknown;
    
    NSString *currency = data[@"currency"];
    NSNumber *amount = data[@"amount"];
    
    NSNumber *purchasedTimestamp = data[@"purchased"];
    NSDate *purchasedDate = [QNUtils dateFromTimestamp:purchasedTimestamp];
    
    NSNumber *createdTimestamp = data[@"created"];
    NSDate *createdDate = [QNUtils dateFromTimestamp:createdTimestamp];
    
    NSDictionary *productData = data[@"product"];
    QNUserProduct *userProduct = [self mapProduct:productData];
     
    QNPurchase *purchase = [[QNPurchase alloc] initWithUserID:userID
                                                   originalID:originalID
                                                purchaseToken:token
                                                     platform:platform
                                             platformRawValue:platformRawValue
                                            platformProductID:platformProductID
                                                      product:userProduct
                                                     currency:currency
                                                       amount:amount.integerValue
                                                 purchaseDate:purchasedDate
                                                   createDate:createdDate
                                                       object:object];
    
    [purchases addObject:purchase];
  }
  
  return purchases;
}

- (NSArray<QNUserProduct *> *)mapProducts:(NSDictionary *)productsData {
  if (productsData.count == 0) {
    return @[];
  }
  
  NSMutableArray<QNUserProduct *> *products = [NSMutableArray new];
  
  for (NSDictionary *data in productsData) {
    QNUserProduct *product = [self mapProduct:data];
    
    [products addObject:product];
  }
  
  return [products copy];
}

- (QNUserProduct *)mapProduct:(NSDictionary *)data {
  NSString *object = data[@"object"];
  NSString *productID = data[@"product_id"];
  
  NSString *currency = data[@"currency"];
  NSNumber *price = data[@"price"];
  NSNumber *introductoryPrice = data[@"introductory_price"];
  NSString *introductoryDuration = data[@"introductory_duration"];
  
  NSString *typeRawValue = data[@"type"];
  NSNumber *typeNumber = self.userProductTypes[typeRawValue];
  QNUserProductType type = typeNumber ? typeNumber.integerValue : QNUserProductTypeUnknown;
  
  NSDictionary *subscriptionData = data[@"subscription"];
  QNSubscription *subscription = [self mapSubscription:subscriptionData];
  
  QNUserProduct *product = [[QNUserProduct alloc] initWithIdentifier:productID
                                                                type:type
                                                            currency:currency
                                                               price:price.integerValue
                                                   introductoryPrice:introductoryPrice.integerValue
                                                introductoryDuration:introductoryDuration
                                                        subscription:subscription
                                                              object:object];
  
  return product;
}

- (QNSubscription *)mapSubscription:(NSDictionary *)subscriptionData {
  NSString *periodDuration = subscriptionData[@"period_duration"];
  NSString *object = subscriptionData[@"object"];
  
  NSNumber *startedTimestamp = subscriptionData[@"started"];
  NSDate *startedDate = [QNUtils dateFromTimestamp:startedTimestamp];
  
  NSNumber *currentPeriodStartTimestamp = subscriptionData[@"current_period_start"];
  NSDate *currentPeriodStartDate = [QNUtils dateFromTimestamp:currentPeriodStartTimestamp];
  
  NSNumber *currentPeriodEndTimestamp = subscriptionData[@"current_period_end"];
  NSDate *currentPeriodEndDate = [QNUtils dateFromTimestamp:currentPeriodEndTimestamp];
  
  NSString *currentPeriodTypeRawValue = subscriptionData[@"current_period_type"];
  NSNumber *currentPeriodTypeNumber = self.currentPeriodTypes[currentPeriodTypeRawValue];
  QNSubscriptionPeriodType currentPeriodType = currentPeriodTypeNumber ? currentPeriodTypeNumber.integerValue : QNSubscriptionPeriodTypeUnknown;
  
  NSString *renewStateRawValue = subscriptionData[@"renew_state"];
  NSNumber *renewStateNumber = self.renewStates[renewStateRawValue];
  QNSubscriptionRenewState renewState = renewStateNumber ? renewStateNumber.integerValue : QNSubscriptionRenewStateUnknown;
  
  QNSubscription *subscription = [[QNSubscription alloc] initWithObject:object
                                                         periodDuration:periodDuration
                                                              startDate:startedDate
                                                 currentPeriodStartDate:currentPeriodStartDate
                                                   currentPeriodEndDate:currentPeriodEndDate
                                              currentPeriodTypeRawValue:currentPeriodTypeRawValue
                                                      currentPeriodType:currentPeriodType
                                                             renewState:renewState];
  
  return subscription;
}

- (NSDictionary *)getDataFromObject:(NSDictionary *)obj {
  NSDictionary *temp = obj[@"data"];
  
  NSDictionary *result = [temp isKindOfClass:[NSDictionary class]] ? temp : nil;
  
  return result;
}

@end
