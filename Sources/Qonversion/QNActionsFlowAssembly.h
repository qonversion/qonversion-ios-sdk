//
//  QNActionsFlowAssembly.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class ActionsViewController;
@protocol ActionsViewControllerDelegate;

NS_ASSUME_NONNULL_BEGIN

@interface QNActionsFlowAssembly : NSObject

- (ActionsViewController *)configureActionsViewControllerWithActionID:(NSString *)actionID delegate:(id<ActionsViewControllerDelegate>)delegate;

@end

NS_ASSUME_NONNULL_END
