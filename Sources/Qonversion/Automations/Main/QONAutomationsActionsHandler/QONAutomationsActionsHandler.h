//
//  QONAutomationsActionsHandler.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class WKNavigationAction, QONActionResult;

NS_ASSUME_NONNULL_BEGIN

@interface QONAutomationsActionsHandler : NSObject

#if !TARGET_OS_TV
- (BOOL)isActionShouldBeHandled:(WKNavigationAction *)action;
- (QONActionResult *)prepareDataForAction:(WKNavigationAction *)action;
#endif

@end

NS_ASSUME_NONNULL_END
