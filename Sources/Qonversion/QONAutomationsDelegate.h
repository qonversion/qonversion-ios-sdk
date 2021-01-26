//
//  QONAutomationsDelegate.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 24.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

@class UIViewController, QONActionResult;

NS_SWIFT_NAME(Qonversion.AutomationsDelegate)
@protocol QONAutomationsDelegate <NSObject>

@optional
- (void)automationFinishedWithAction:(QONActionResult * _Nonnull)action
NS_SWIFT_NAME(automationFinished(action:));;
- (UIViewController * _Nonnull)controllerForNavigation
NS_SWIFT_NAME(controllerForNavigation());;

@end
