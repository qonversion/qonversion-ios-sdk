//
//  QONEntitlementsCacheLifetime.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 20.07.2022.
//  Copyright © 2022 Qonversion Inc. All rights reserved.
//

typedef NS_ENUM(NSInteger, QONEntitlementsCacheLifetime) {
  QONEntitlementsCacheLifetimeWeek = 1,
  QONEntitlementsCacheLifetimeTwoWeeks = 2,
  QONEntitlementsCacheLifetimeMonth = 3,
  QONEntitlementsCacheLifetimeTwoMonths = 4,
  QONEntitlementsCacheLifetimeThreeMonths = 5,
  QONEntitlementsCacheLifetimeSixMonths = 6,
  QONEntitlementsCacheLifetimeYear = 7,
  QONEntitlementsCacheLifetimeUnlimited = 8,
} NS_SWIFT_NAME(Qonversion.EntitlementsCacheLifetime);
