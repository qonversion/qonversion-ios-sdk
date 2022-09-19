//
//  QONAutomationsEvent+Protected.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.07.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QONAutomationsEvent.h"

NS_ASSUME_NONNULL_BEGIN

@interface QONAutomationsEvent (Protected)

- (instancetype)initWithType:(QONAutomationsEventType)type date:(NSDate *)date productId:(NSString *)productId;

@end

NS_ASSUME_NONNULL_END

