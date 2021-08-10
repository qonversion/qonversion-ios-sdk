//
//  QONAutomationsEvent.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.07.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QONAutomationsEventType.h"

NS_ASSUME_NONNULL_BEGIN

@interface QONAutomationsEvent : NSObject

@property (nonatomic, assign, readonly) QONAutomationsEventType type;
@property (nonatomic, strong, readonly) NSDate *date;

@end

NS_ASSUME_NONNULL_END
