//
//  ActionsFlowCoordinator.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 24.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol ActionsDelegate;

NS_ASSUME_NONNULL_BEGIN

@interface ActionsFlowCoordinator : NSObject

+ (instancetype)sharedInstance;

- (void)setActionsDelegate:(id<ActionsDelegate> _Nullable)actionsDelegate;
- (void)showActionWithID:(NSString *)actionID;

@end

NS_ASSUME_NONNULL_END
