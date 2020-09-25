//
//  ActionsDelegate.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 24.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

@class UIViewController;

NS_SWIFT_NAME(Qonversion.ActionsDelegate)
@protocol ActionsDelegate <NSObject>

@optional
- (void)actionFlowFinished;
- (BOOL)canShowActionWithID:(NSString *)actionID;
- (UIViewController *)controllerForNavigation;

@end
