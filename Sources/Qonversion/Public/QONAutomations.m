//
//  QONAutomations.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 24.01.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

#if TARGET_OS_IOS
#import "QONAutomations.h"
#import "QONAutomationsFlowCoordinator.h"

@interface QONAutomations ()

@property (nonatomic, weak) id<QONAutomationsDelegate> automationsDelegate;

@end

@implementation QONAutomations

+ (void)setDelegate:(id<QONAutomationsDelegate>)delegate {
  [[QONAutomationsFlowCoordinator sharedInstance] setAutomationsDelegate:delegate];
}

+ (void)showScreenWithID:(NSString *)screenID completion:(nullable QONShowScreenCompletionHandler)completion {
  [[QONAutomationsFlowCoordinator sharedInstance] showAutomationWithID:screenID completion:completion];
}

@end

#endif
