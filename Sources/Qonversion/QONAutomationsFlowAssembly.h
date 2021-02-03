//
//  QONAutomationsFlowAssembly.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class QONAutomationsViewController, QONAutomationsService, QONAutomationsActionsHandler, QONAutomationsScreen;
@protocol QONAutomationsViewControllerDelegate;

NS_ASSUME_NONNULL_BEGIN

@interface QONAutomationsFlowAssembly : NSObject

- (QONAutomationsViewController *)configureAutomationsViewControllerWithScreen:(QONAutomationsScreen *)screen delegate:(id<QONAutomationsViewControllerDelegate> _Nullable)delegate;
- (QONAutomationsService *)automationsService;
- (QONAutomationsActionsHandler *)actionsHandler;

@end

NS_ASSUME_NONNULL_END