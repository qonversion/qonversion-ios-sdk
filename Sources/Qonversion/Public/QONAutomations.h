//
//  QONAutomations.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 24.01.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

#if TARGET_OS_IOS

@protocol QONAutomationsDelegate, QONScreenCustomizationDelegate;

typedef void (^QONShowScreenCompletionHandler)(BOOL success, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.ShowScreenCompletionHandler);

NS_ASSUME_NONNULL_BEGIN

API_AVAILABLE(ios(9.0))
NS_SWIFT_NAME(Qonversion.Automations)
@interface QONAutomations : NSObject

/**
 Use `sharedInstance` instead.
 */
- (instancetype)init NS_UNAVAILABLE;

/**
 Use this variable to get a current initialized instance of the Automations part of Qonversion SDK.
 Please, use the variable only after initializing Qonversion SDK.
 @return Current initialized instance of the Automations.
 */
+ (instancetype)sharedInstance NS_SWIFT_NAME(shared());

/**
 The delegate is responsible for handling in-app screens and actions result when push notification is received.
 @param delegate - delegate that is called when in-app screens and actions are processed
 */
- (void)setDelegate:(nonnull id<QONAutomationsDelegate>)delegate
NS_SWIFT_NAME(setDelegate(_:));

/**
 The delegate is responsible for customizing screens representation
 @param delegate - delegate that is called before opening Qonversion screens
 */
- (void)setScreenCustomizationDelegate:(nonnull id<QONScreenCustomizationDelegate>)delegate
NS_SWIFT_NAME(setScreenCustomizationDelegate(_:));

/**
 Show the screen using its ID
 @param screenID - screen's ID that must be shown
 @param completion - completion that is called when the screen is shown to a user or an error occurred
 */
- (void)showScreenWithID:(nonnull NSString *)screenID completion:(nullable QONShowScreenCompletionHandler)completion;

/**
 Set push token to Qonversion to enable Qonversion push notifications
 @param token - token data
 */
- (void)setNotificationsToken:(nonnull NSData *)token API_AVAILABLE(ios(9.0));

/**
 Returns true when a push notification was received from Qonversion.
 Otherwise returns false, so you need to handle a notification yourself
 @param userInfo - notification user info
 */
- (BOOL)handleNotification:(nonnull NSDictionary *)userInfo API_AVAILABLE(ios(9.0));

/**
 Get parsed custom payload, which you added to the notification in the dashboard
 @param userInfo - notification user info
 @return a map with custom payload from the notification or nil if it's not provided.
 */
- (NSDictionary *_Nullable)getNotificationCustomPayload:(nonnull NSDictionary *)userInfo;

@end

NS_ASSUME_NONNULL_END

#endif
