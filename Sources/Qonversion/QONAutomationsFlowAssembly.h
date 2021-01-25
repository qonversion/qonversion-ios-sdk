//
//  QONAutomationsFlowAssembly.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class QONAutomationsViewController, QONAutomationsService, QONAutomationsActionsHandler;
@protocol QNAutomationsViewControllerDelegate;

NS_ASSUME_NONNULL_BEGIN

@interface QONAutomationsFlowAssembly : NSObject

- (QONAutomationsViewController *)configureAutomationsViewControllerWithHtmlString:(NSString *)htmlString delegate:(id<QNAutomationsViewControllerDelegate> _Nullable)delegate;
- (QONAutomationsService *)automationsService;
- (QONAutomationsActionsHandler *)actionsHandler;

@end

NS_ASSUME_NONNULL_END
