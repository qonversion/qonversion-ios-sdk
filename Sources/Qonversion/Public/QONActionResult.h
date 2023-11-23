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
  QONActionResultTypeUnknown = 0,
  QONActionResultTypeURL = 1,
  QONActionResultTypeDeeplink = 2,
  QONActionResultTypeNavigation = 3,
  QONActionResultTypePurchase = 4,
  QONActionResultTypeRestore = 5,
  QONActionResultTypeClose = 6,
  QONActionResultTypeCloseAll = 7
} NS_SWIFT_NAME(Qonversion.ActionResultType);

NS_SWIFT_NAME(Qonversion.ActionResult)
@interface QONActionResult : NSObject

@property (nonatomic, assign) QONActionResultType type;
@property (nonatomic, copy, nullable) NSDictionary *parameters;
@property (nonatomic, strong, nullable) NSError *error;

@end

NS_ASSUME_NONNULL_END
