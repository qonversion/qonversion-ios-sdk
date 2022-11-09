//
//  QONLaunchMode.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 08.11.2022.
//  Copyright © 2022 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, QONLaunchMode) {
  QONLaunchModeAnalytics = 1,
  QONLaunchModeSubscriptionManagement = 2
} NS_SWIFT_NAME(Qonversion.LaunchMode);
