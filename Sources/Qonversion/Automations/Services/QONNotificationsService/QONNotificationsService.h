//
//  QONNotificationsService.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 15.11.2022.
//  Copyright © 2022 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QNAPIClient.h"

NS_ASSUME_NONNULL_BEGIN

@interface QONNotificationsService : NSObject

@property (nonatomic, strong) QNAPIClient *apiClient;

- (void)sendPushToken;

@end

NS_ASSUME_NONNULL_END
