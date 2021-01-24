//
//  QNAutomationsFlowAssembly.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class QNAutomationsViewController, QNAutomationsService, QNActionsHandler;
@protocol QNAutomationsViewControllerDelegate;

NS_ASSUME_NONNULL_BEGIN

@interface QNAutomationsFlowAssembly : NSObject

- (QNAutomationsViewController *)configureAutomationsViewControllerWithHtmlString:(NSString *)htmlString delegate:(id<QNAutomationsViewControllerDelegate> _Nullable)delegate;
- (QNAutomationsService *)automationService;
- (QNActionsHandler *)actionsHandler;

@end

NS_ASSUME_NONNULL_END
