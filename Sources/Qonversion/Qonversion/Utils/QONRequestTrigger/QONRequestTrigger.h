//
//  QNRequestTrigger.h
//  Qonversion
//
//  Created by Kamo Spertsyan on 19.03.2025.
//  Copyright © 2025 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, QONRequestTrigger) {
    QONRequestTriggerInit = 0,
    QONRequestTriggerPurchase,
    QONRequestTriggerProducts,
    QONRequestTriggerRestore,
    QONRequestTriggerSyncHistoricalData,
    QONRequestTriggerActualizePermissions,
    QONRequestTriggerIdentify,
    QONRequestTriggerLogout,
    QONRequestTriggerUserProperties,
    QONRequestTriggerHandleStoreKit2Transactions,
} NS_SWIFT_NAME(Qonversion.RequestTrigger);
