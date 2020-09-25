//
//  QNAction.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, QNActionType) {
  QNActionTypeUnknown = 0,
  QNActionTypeLink,
  QNActionTypeDeeplink,
  QNActionTypeNaivgation,
  QNActionTypePurchase,
  QNActionTypeRestorePurchases,
  QNActionTypeClose
} NS_SWIFT_NAME(Qonversion.ActionType);

@interface QNAction : NSObject

@property (nonatomic, assign) QNActionType type;
@property (nonatomic, copy) NSDictionary *value;

@end

NS_ASSUME_NONNULL_END
