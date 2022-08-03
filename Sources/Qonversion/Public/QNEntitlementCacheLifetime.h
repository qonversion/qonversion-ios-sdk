//
//  QNEntitlementCacheLifetime.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 20.07.2022.
//  Copyright © 2022 Qonversion Inc. All rights reserved.
//

typedef NS_ENUM(NSInteger, QNEntitlementCacheLifetime) {
  QNEntitlementCacheLifetimeWeek = 1,
  QNEntitlementCacheLifetimeTwoWeeks = 2,
  QNEntitlementCacheLifetimeMonth = 3,
  QNEntitlementCacheLifetimeTwoMonth = 4,
  QNEntitlementCacheLifetimeThreeMonth = 5,
  QNEntitlementCacheLifetimeSixMonth = 6,
  QNEntitlementCacheLifetimeYear = 7,
  QNEntitlementCacheLifetimeUnlimited = 8,
} NS_SWIFT_NAME(Qonversion.EntitlementCacheLifetime);
