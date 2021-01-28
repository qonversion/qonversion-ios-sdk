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
- (void)automationsDidShowScreen:(NSString * _Nonnull)screenID
NS_SWIFT_NAME(automationsDidShowScreen(id:));

- (void)automationsDidStartExecutingActionResult:(QONActionResult * _Nonnull)actionResult
NS_SWIFT_NAME(automationsDidStartExecuting(actionResult:));

- (void)automationsDidFailExecutingActionResult:(QONActionResult * _Nonnull)actionResult
NS_SWIFT_NAME(automationsDidFailExecuting(actionResult:));

- (void)automationsDidFinishExecutingActionResult:(QONActionResult * _Nonnull)actionResult
NS_SWIFT_NAME(automationsDidFinishExecuting(actionResult:));

- (void)automationsFinished
NS_SWIFT_NAME(automationsFinished());

- (UIViewController * _Nonnull)controllerForNavigation
NS_SWIFT_NAME(controllerForNavigation());

@end
