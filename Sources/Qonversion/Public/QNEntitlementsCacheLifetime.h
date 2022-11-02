//
//  QNEntitlementsCacheLifetime.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 20.07.2022.
//  Copyright © 2022 Qonversion Inc. All rights reserved.
//

typedef NS_ENUM(NSInteger, QNEntitlementsCacheLifetime) {
  QNEntitlementsCacheLifetimeWeek = 1,
  QNEntitlementsCacheLifetimeTwoWeeks = 2,
  QNEntitlementsCacheLifetimeMonth = 3,
  QNEntitlementsCacheLifetimeTwoMonths = 4,
  QNEntitlementsCacheLifetimeThreeMonths = 5,
  QNEntitlementsCacheLifetimeSixMonths = 6,
  QNEntitlementsCacheLifetimeYear = 7,
  QNEntitlementsCacheLifetimeUnlimited = 8,
} NS_SWIFT_NAME(Qonversion.EntitlementsCacheLifetime);
