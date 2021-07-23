//
//  QONAutomationsEventsMapper.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 21.07.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class QONAutomationsEvent;

NS_ASSUME_NONNULL_BEGIN

@interface QONAutomationsEventsMapper : NSObject

- (QONAutomationsEvent * _Nullable)eventFromNotification:(NSDictionary<NSString *, id> *)notificationInfo;

@end

NS_ASSUME_NONNULL_END
