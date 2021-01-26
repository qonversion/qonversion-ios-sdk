//
//  QONActionResult.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, QONActionResultType) {
  QONActionTypeUnknown = 0,
  QONActionTypeURL = 1,
  QONActionTypeDeeplink = 2,
  QONActionTypeNavigation = 3,
  QONActionTypePurchase = 4,
  QONActionTypeRestore = 5,
  QONActionTypeClose = 6
} NS_SWIFT_NAME(Qonversion.ActionResultType);

NS_SWIFT_NAME(Qonversion.ActionResult)
@interface QONActionResult : NSObject

@property (nonatomic, assign) QONActionResultType type;
@property (nonatomic, copy) NSDictionary *value;

@end

NS_ASSUME_NONNULL_END
