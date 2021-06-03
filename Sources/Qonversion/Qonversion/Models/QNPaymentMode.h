//
//  QNPaymentMode.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 20.05.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, QNPaymentMode) {
  QNPaymentModeUnknown = -1,
  QNPaymentModePayAsYouGo = 1,
  QNPaymentModePayUpFront = 2,
  QNPaymentModeFreeTrial = 3
} NS_SWIFT_NAME(Qonversion.PaymentMode);
