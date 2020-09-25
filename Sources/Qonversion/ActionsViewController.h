//
//  ActionsViewController.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import <UIKit/UIKit.h>

@class QNActionsService, QNActionsHandler, QNActionsFlowAssembly, ActionsViewController, QNAction;

@protocol ActionsViewControllerDelegate <NSObject>

- (void)actionViewController:(ActionsViewController *)viewController didFinishAction:(QNAction *)action;

@end

NS_ASSUME_NONNULL_BEGIN

@interface ActionsViewController : UIViewController

@property (nonatomic, weak) id<ActionsViewControllerDelegate> delegate;
@property (nonatomic, copy) NSString *actionID;
@property (nonatomic, strong) QNActionsHandler *actionsHandler;
@property (nonatomic, strong) QNActionsService *actionsService;
@property (nonatomic, strong) QNActionsFlowAssembly *flowAssembly;

@end

NS_ASSUME_NONNULL_END

