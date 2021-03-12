//
//  QONAutomationsViewController.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

#if TARGET_OS_IOS
#import <UIKit/UIKit.h>

@class QONAutomationsService, QONAutomationsScreen, QONAutomationsActionsHandler, QONAutomationsFlowAssembly, QONActionResult, QONAutomationsViewController, QONAutomationsScreenProcessor;

NS_ASSUME_NONNULL_BEGIN

@protocol QONAutomationsViewControllerDelegate <NSObject>

- (void)automationsDidShowScreen:(NSString *)screenID;
- (void)automationsDidStartExecutingActionResult:(QONActionResult * _Nonnull)actionResult;
- (void)automationsDidFailExecutingActionResult:(QONActionResult * _Nonnull)actionResult;
- (void)automationsDidFinishExecutingActionResult:(QONActionResult * _Nonnull)actionResult;
- (void)automationsFinished;

@end
@interface QONAutomationsViewController : UIViewController

@property (nonatomic, weak) id<QONAutomationsViewControllerDelegate> delegate;
@property (nonatomic, strong) QONAutomationsScreen *screen;
@property (nonatomic, strong) QONAutomationsActionsHandler *actionsHandler;
@property (nonatomic, strong) QONAutomationsService *automationsService;
@property (nonatomic, strong) QONAutomationsFlowAssembly *flowAssembly;
@property (nonatomic, strong) QONAutomationsScreenProcessor *screenProcessor;

@end

NS_ASSUME_NONNULL_END

#endif
