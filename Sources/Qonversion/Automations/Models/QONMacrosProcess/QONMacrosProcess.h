//
//  QONMacrosProcess.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 01.04.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, QONScreenMacrosType) {
  QONScreenMacrosTypeUnknown = 0,
  QONScreenMacrosTypeProductPrice = 1,
  QONScreenMacrosTypeProductSubscriptionDuration = 2,
  QONScreenMacrosTypeProductTrialDuration = 3
};

@interface QONMacrosProcess : NSObject

@property (nonatomic, assign) QONScreenMacrosType type;
@property (nonatomic, copy) NSString *productID;
@property (nonatomic, copy) NSString *initialMacrosString;

@end

NS_ASSUME_NONNULL_END
