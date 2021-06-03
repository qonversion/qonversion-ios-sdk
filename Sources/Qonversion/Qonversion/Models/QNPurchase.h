//
//  QNPurchase.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 14.05.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class QNUserProduct;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, QNPurchasePlatform) {
  QNPurchasePlatformUnknown = -1,
  QNPurchasePlatformIOS = 1,
  QNPurchasePlatformAndroid = 2,
  QNPurchasePlatformStripe = 3,
  QNPurchasePlatformPromo = 4
} NS_SWIFT_NAME(Qonversion.PurchasePlatform);

@interface QNPurchase : NSObject

@property (nonatomic, copy, readonly) NSString *userID;
@property (nonatomic, copy, readonly) NSString *originalID;
@property (nonatomic, copy, readonly) NSString *purchaseToken;
@property (nonatomic, assign, readonly) QNPurchasePlatform platform;
@property (nonatomic, copy, readonly) NSString *platformRawValue;
@property (nonatomic, copy, readonly) NSString *platformProductID;
@property (nonatomic, strong, readonly) QNUserProduct *product;
@property (nonatomic, copy, readonly) NSString *currency;
@property (nonatomic, assign, readonly) NSUInteger amount;
@property (nonatomic, strong, readonly) NSDate *purchaseDate;
@property (nonatomic, strong, readonly) NSDate *createDate;
@property (nonatomic, copy, readonly) NSString *object;

@end

NS_ASSUME_NONNULL_END
