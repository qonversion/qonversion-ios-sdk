//
//  QNUserProduct.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 14.05.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QNPaymentMode.h"

@class QNSubscription;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, QNUserProductType){
  QNUserProductTypeUnknown = -1,
  QNUserProductTypeNonRecurring = 1,
  QNUserProductTypeSubscription = 2
} NS_SWIFT_NAME(Qonversion.UserProductType);

@interface QNUserProduct : NSObject

@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, assign, readonly) QNUserProductType type;
@property (nonatomic, copy, readonly) NSString *currency;
@property (nonatomic, assign, readonly) NSInteger price;
@property (nonatomic, assign, readonly) NSInteger introductoryPrice;
@property (nonatomic, assign, readonly) QNPaymentMode introductoryPaymentMode;
@property (nonatomic, copy, readonly) NSString *introductoryDuration;
@property (nonatomic, strong, readonly) QNSubscription *subscription;
@property (nonatomic, copy, readonly) NSString *object;

@end

NS_ASSUME_NONNULL_END
