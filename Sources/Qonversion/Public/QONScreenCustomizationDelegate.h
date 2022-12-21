//
//  QONScreenCustomizationDelegate.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 21.12.2022.
//  Copyright © 2022 Qonversion Inc. All rights reserved.
//

#import "QONScreenTransitionConfiguration.h"

/**
 The delegate is responsible for customazing screens open logic (transition style, animation. etc).
 */
NS_SWIFT_NAME(Qonversion.ScreenCustomizationDelegate)
@protocol QONScreenCustomizationDelegate <NSObject>

@optional

/**
 The function should return the screen transactions configuration used to present the first screen in the chain.
 @return screen transaction configuration. Use `[QONScreenTransitionConfiguration defaultConfiguration]` if you don't want to override it for specific screens ids
 */
- (QONScreenTransitionConfiguration * _Nonnull)transactionConfigurationForScreen:(NSString * _Nonnull)screenId
NS_SWIFT_NAME(transactionConfigurationForScreen(_:));;

@end
