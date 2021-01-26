//
//  QONAutomations.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 24.01.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol QONAutomationsDelegate;

NS_ASSUME_NONNULL_BEGIN

API_AVAILABLE(ios(9.0))
NS_SWIFT_NAME(Qonversion.Automations)
@interface QONAutomations : NSObject

+ (void)setDelegate:(id<QONAutomationsDelegate>)delegate
NS_SWIFT_NAME(setDelegate(_:));

@end

NS_ASSUME_NONNULL_END
