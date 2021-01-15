//
//  QNIntroEligibility.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 14.01.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, QNIntroEligibilityStatus) {
  QNIntroEligibilityStatusUnknown = 0,
  QNIntroEligibilityStatusNonIntroProduct,
  QNIntroEligibilityStatusIneligible,
  QNIntroEligibilityStatusEligible
} NS_SWIFT_NAME(Qonversion.IntroEligibilityStatus);

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(Qonversion.IntroEligibility)
@interface QNIntroEligibility : NSObject

@property (nonatomic, assign, readonly) QNIntroEligibilityStatus status;

@end

NS_ASSUME_NONNULL_END
