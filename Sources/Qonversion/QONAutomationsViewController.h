//
//  QONAutomationsViewController.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import <UIKit/UIKit.h>

@class QONAutomationsService, QONAutomationsActionsHandler, QONAutomationsFlowAssembly, QONActionResult, QONAutomationsViewController;

NS_ASSUME_NONNULL_BEGIN

@protocol QNAutomationsViewControllerDelegate <NSObject>

- (void)automationsViewController:(QONAutomationsViewController *)viewController didFinishAction:(QONActionResult *)action;

@end

@interface QONAutomationsViewController : UIViewController

@property (nonatomic, weak) id<QNAutomationsViewControllerDelegate> delegate;
@property (nonatomic, copy) NSString *htmlString;
@property (nonatomic, strong) QONAutomationsActionsHandler *actionsHandler;
@property (nonatomic, strong) QONAutomationsService *automationsService;
@property (nonatomic, strong) QONAutomationsFlowAssembly *flowAssembly;

@end

NS_ASSUME_NONNULL_END

