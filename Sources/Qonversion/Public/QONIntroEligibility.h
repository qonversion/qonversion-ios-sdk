//
//  QONIntroEligibility.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 14.01.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, QONIntroEligibilityStatus) {
  QONIntroEligibilityStatusUnknown = 0,
  QONIntroEligibilityStatusNonIntroProduct,
  QONIntroEligibilityStatusIneligible,
  QONIntroEligibilityStatusEligible
} NS_SWIFT_NAME(Qonversion.IntroEligibilityStatus);

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(Qonversion.IntroEligibility)
@interface QONIntroEligibility : NSObject

@property (nonatomic, assign, readonly) QONIntroEligibilityStatus status;

@end

NS_ASSUME_NONNULL_END
