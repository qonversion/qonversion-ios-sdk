//
//  QONScreenTransitionConfiguration.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 20.12.2022.
//  Copyright © 2022 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, QONScreenPresentationStyle) {
  /**
   UIModalPresentationPopover analog
   */
  QONScreenPresentationStylePopover = 1,
  
  /**
   Not a modal presentation. This style pushes a controller to a current navigation stack.
   */
  QONScreenPresentationStylePush = 2,
  
  /**
   UIModalPresentationFullScreen analog
   */
  QONScreenPresentationStyleFullScreen = 3
} NS_SWIFT_NAME(Qonversion.ScreenPresentationStyle);

NS_SWIFT_NAME(Qonversion.ScreenTransitionConfiguration)
@interface QONScreenTransitionConfiguration : NSObject

@property (nonatomic, assign, readonly) QONScreenPresentationStyle presentationStyle;
@property (nonatomic, assign, readonly) BOOL animated;

/**
 Default iinitializer of QONScreenTransitionConfiguration.
 @return the initialized instance of QONScreenTransitionConfiguration with animated QONScreenPresentationStyleFullScreen
 */
+ (instancetype)defaultConfiguration;

/**
 Iinitializer of QONScreenTransitionConfiguration.
 @param presentationStyle - style that be used to present screen.
 @return the initialized instance of QONScreenTransitionConfiguration.
 */
- (instancetype)initWithPresentationStyle:(QONScreenPresentationStyle)presentationStyle;

/**
 Iinitializer of QONScreenTransitionConfiguration.
 @param presentationStyle - a style that defines screen presentation type
 @param animated - the flag that enables/disables screen presentation animation
 @return the initialized instance of QONScreenTransitionConfiguration
 */
- (instancetype)initWithPresentationStyle:(QONScreenPresentationStyle)presentationStyle animated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
