//
//  QONAction.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, QONActionType) {
  QONActionTypeUnknown = 0,
  QONActionTypeLink,
  QONActionTypeDeeplink,
  QONActionTypeNaivgation,
  QONActionTypePurchase,
  QONActionTypeRestorePurchases,
  QONActionTypeClose
} NS_SWIFT_NAME(Qonversion.ActionType);

@interface QONAction : NSObject

@property (nonatomic, assign) QONActionType type;
@property (nonatomic, copy) NSDictionary *value;

@end

NS_ASSUME_NONNULL_END
