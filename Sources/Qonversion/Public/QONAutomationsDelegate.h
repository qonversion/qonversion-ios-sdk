//
//  QONAutomationsDelegate.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 24.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import "QONAutomationsEventType.h"
#import "QONActionResult.h"
#import "QONAutomationsEvent.h"

@class UIViewController;

/**
 The delegate is responsible for handling in-app screens and actions when push notification is received.
 Make sure the method is called before handlePushIfPossible
 */
NS_SWIFT_NAME(Qonversion.AutomationsDelegate)
@protocol QONAutomationsDelegate <NSObject>

@optional

/**
 Called when Automation event is being processed.
 For example, you have set up push notifications for various events, such as purchase, cancellation of trial, etc.
 If Qonversion sent a push notification with an event, and you want to handle the event yourself (for example, show your custom screen),
 then override this function and return false.
 Otherwise, Qonversion will handle this event itself and show the Automation screen (if it's configured).
 @param event - event that triggered the Automation
 @param payload - notification payload
 @return the flag that indicates should Qonversion handle the event or not
 @see [Automation Overview](https://documentation.qonversion.io/docs/automations)
 */
- (BOOL)shouldHandleEvent:(QONAutomationsEvent * _Nonnull)event payload:(NSDictionary<NSString *, id> * _Nonnull)payload
NS_SWIFT_NAME(shouldHandleEvent(_:payload:));

/**
 Called when Automations screen is shown
 @param screenID - shown screen Id
 */
- (void)automationsDidShowScreen:(NSString * _Nonnull)screenID
NS_SWIFT_NAME(automationsDidShowScreen(_:));

/**
 Called when Automations flow starts executing an action
 @param actionResult - executed action
 */
- (void)automationsDidStartExecutingActionResult:(QONActionResult * _Nonnull)actionResult
NS_SWIFT_NAME(automationsDidStartExecuting(actionResult:));

/**
 Called when Automations flow fails executing an action
 @param actionResult - executed action
 */
- (void)automationsDidFailExecutingActionResult:(QONActionResult * _Nonnull)actionResult
NS_SWIFT_NAME(automationsDidFailExecuting(actionResult:));

/**
 Called when Automations flow finishes executing an action
 @param actionResult - executed action.
 For instance, if the user made a purchase then action.type == QONActionResultTypePurchase
 Then you can use the Qonversion.checkEntitlements() method to get available entitlements
 */
- (void)automationsDidFinishExecutingActionResult:(QONActionResult * _Nonnull)actionResult
NS_SWIFT_NAME(automationsDidFinishExecuting(actionResult:));

/**
 Called when Automations flow is finished and the Automations screen is closed
 */
- (void)automationsFinished
NS_SWIFT_NAME(automationsFinished());

/**
 Return a source ViewController for navigation
 */
- (UIViewController * _Nonnull)controllerForNavigation
NS_SWIFT_NAME(controllerForNavigation());

@end
