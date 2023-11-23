//
//  QONAutomationsFlowCoordinator.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 24.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QONAutomations.h"

@protocol QONAutomationsDelegate;

NS_ASSUME_NONNULL_BEGIN

@interface QONAutomationsFlowCoordinator : NSObject

+ (instancetype)sharedInstance;

- (void)didFinishLaunch;

- (void)setAutomationsDelegate:(id<QONAutomationsDelegate> _Nullable)automationsDelegate;
- (void)setScreenCustomizationDelegate:(id<QONScreenCustomizationDelegate>)screenCustomizationDelegate;
- (void)showAutomationWithID:(NSString *)automationID completion:(nullable QONShowScreenCompletionHandler)completion;
- (BOOL)handlePushNotification:(NSDictionary *)userInfo;
- (void)showAutomationIfExists;
- (void)sendPushToken:(NSData *)pushTokenData;

@end

NS_ASSUME_NONNULL_END
