//
//  QNAutomationsMapper.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.12.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class QNAutomationScreen, QNUserActionPoint;

NS_ASSUME_NONNULL_BEGIN

@interface QNAutomationsMapper : NSObject

- (nullable QNAutomationScreen *)mapScreen:(NSDictionary *)dict;
- (nullable NSError *)mapError:(NSDictionary *)error;
- (NSArray<QNUserActionPoint *> *)mapUserActionPoints:(NSArray<NSDictionary *> *)data;

@end

NS_ASSUME_NONNULL_END
