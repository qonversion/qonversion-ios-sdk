//
//  QNAutomationsDelegate.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 24.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

@class UIViewController, QNAction;

NS_SWIFT_NAME(Qonversion.AutomationsDelegate)
@protocol QNAutomationsDelegate <NSObject>

@optional
- (void)automationFlowFinishedWithAction:(QNAction *)action;
- (UIViewController *)controllerForNavigation;

@end
