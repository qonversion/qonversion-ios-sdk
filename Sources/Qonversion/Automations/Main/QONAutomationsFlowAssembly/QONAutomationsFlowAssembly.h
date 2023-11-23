//
//  QONAutomationsFlowAssembly.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

#if TARGET_OS_IOS

@class QONAutomationsViewController, QONAutomationsService, QONAutomationsActionsHandler, QONAutomationsScreen, QONAutomationsEventsMapper, QONNotificationsService;
@protocol QONAutomationsViewControllerDelegate;

NS_ASSUME_NONNULL_BEGIN

@interface QONAutomationsFlowAssembly : NSObject

- (QONAutomationsViewController *)configureAutomationsViewControllerWithScreen:(QONAutomationsScreen *)screen delegate:(id<QONAutomationsViewControllerDelegate> _Nullable)delegate;
- (QONAutomationsService *)automationsService;
- (QONAutomationsActionsHandler *)actionsHandler;
- (QONAutomationsEventsMapper *)eventsMapper;
- (QONNotificationsService *)notificationsService;

@end

NS_ASSUME_NONNULL_END
#endif
