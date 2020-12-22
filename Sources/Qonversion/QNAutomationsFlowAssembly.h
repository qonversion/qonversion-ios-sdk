//
//  QNAutomationsFlowAssembly.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class QNAutomationsViewController;
@protocol QNAutomationsViewControllerDelegate;

NS_ASSUME_NONNULL_BEGIN

@interface QNAutomationsFlowAssembly : NSObject

- (QNAutomationsViewController *)configureAutomationsViewControllerWithID:(NSString *)automationID delegate:(id<QNAutomationsViewControllerDelegate>)delegate;

@end

NS_ASSUME_NONNULL_END
