//
//  QONAutomations.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 24.01.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

#if TARGET_OS_IOS

@protocol QONAutomationsDelegate;

typedef void (^QONShowScreenCompletionHandler)(BOOL success, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.ShowScreenCompletionHandler);

NS_ASSUME_NONNULL_BEGIN

API_AVAILABLE(ios(9.0))
NS_SWIFT_NAME(Qonversion.Automations)
@interface QONAutomations : NSObject

/**
 The delegate is responsible for handling in-app screens and actions result when push notification is received.
 @param delegate - delegate that is called when in-app screens and actions are processed
 */
+ (void)setDelegate:(id<QONAutomationsDelegate>)delegate
NS_SWIFT_NAME(setDelegate(_:));

/**
 Show the screen using its ID
 @param screenID - screen's ID that must be shown
 @param completion - completion that is called when the screen is shown to a user or an error occurred
 */
+ (void)showScreenWithID:(NSString *)screenID completion:(nullable QONShowScreenCompletionHandler)completion;

@end

NS_ASSUME_NONNULL_END

#endif
