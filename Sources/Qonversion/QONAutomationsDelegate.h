//
//  QONAutomationsDelegate.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 24.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

@class UIViewController, QONAction;

NS_SWIFT_NAME(Qonversion.AutomationsDelegate)
@protocol QONAutomationsDelegate <NSObject>

@optional
- (void)automationFlowFinishedWithAction:(QONAction *)action;
- (UIViewController *)controllerForNavigation;

@end
