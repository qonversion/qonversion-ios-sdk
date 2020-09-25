//
//  QNActionsHandler.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class WKNavigationAction, QNAction;

NS_ASSUME_NONNULL_BEGIN

@interface QNActionsHandler : NSObject

- (BOOL)isActionShouldBeHandled:(WKNavigationAction *)action;
- (QNAction *)prepareDataForAction:(WKNavigationAction *)action;

@end

NS_ASSUME_NONNULL_END
