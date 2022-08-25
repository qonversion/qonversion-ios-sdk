//
//  QNPermissionsCacheLifetime.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 20.07.2022.
//  Copyright © 2022 Qonversion Inc. All rights reserved.
//

typedef NS_ENUM(NSInteger, QNPermissionsCacheLifetime) {
  QNPermissionsCacheLifetimeWeek = 1,
  QNPermissionsCacheLifetimeTwoWeeks = 2,
  QNPermissionsCacheLifetimeMonth = 3,
  QNPermissionsCacheLifetimeTwoMonths = 4,
  QNPermissionsCacheLifetimeThreeMonths = 5,
  QNPermissionsCacheLifetimeSixMonths = 6,
  QNPermissionsCacheLifetimeYear = 7,
  QNPermissionsCacheLifetimeUnlimited = 8,
} NS_SWIFT_NAME(Qonversion.PermissionsCacheLifetime);
