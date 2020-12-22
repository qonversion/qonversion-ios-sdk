//
//  QNAutomationsFlowCoordinator.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 24.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol QNAutomationsDelegate;

NS_ASSUME_NONNULL_BEGIN

@interface QNAutomationsFlowCoordinator : NSObject

+ (instancetype)sharedInstance;

- (void)setAutomationsDelegate:(id<QNAutomationsDelegate> _Nullable)automationsDelegate;
- (void)showAutomationWithID:(NSString *)automationID;

@end

NS_ASSUME_NONNULL_END
