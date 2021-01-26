//
//  QONAutomationsDelegate.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 24.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

@class UIViewController, QONActionResult;

/**
 The delegate is responsible for handling in-app screens and actions when push notification is received.
 Make sure the method is called before handlePushIfPossible
 */
NS_SWIFT_NAME(Qonversion.AutomationsDelegate)
@protocol QONAutomationsDelegate <NSObject>

@optional
- (void)automationFinishedWithAction:(QONActionResult * _Nonnull)action
NS_SWIFT_NAME(automationFinished(action:));;
- (UIViewController * _Nonnull)controllerForNavigation
NS_SWIFT_NAME(controllerForNavigation());;

@end
